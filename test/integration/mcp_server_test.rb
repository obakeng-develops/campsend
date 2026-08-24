require "test_helper"

class McpServerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    _, @raw_token = ApiToken.issue_for(@user, name: "Agent", scope: "read")
  end

  test "a missing, malformed or revoked token is answered, never redirected" do
    call("tools/list", token: nil)
    assert_response :unauthorized
    assert_equal "2.0", json["jsonrpc"]
    assert_match(/API token/, json.dig("error", "message"))

    call("tools/list", token: "not-a-campsend-token")
    assert_response :unauthorized

    token, raw = ApiToken.issue_for(@user, name: "Doomed", scope: "read")
    token.revoke!
    call("tools/list", token: raw)
    assert_response :unauthorized

    # The sign-in redirect would be a 302 a client cannot act on.
    assert_not response.redirect?
  end

  test "a browser session is not a credential here" do
    # Forgery protection is skipped because the credential is a bearer token, so
    # a signed-in cookie must not be able to reach this endpoint at all.
    login_token, raw_login = LoginToken.issue_for(@user)
    post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_login }

    call("tools/list", token: nil)

    assert_response :unauthorized
  end

  test "the handshake a client actually sends works" do
    call("initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })

    assert_response :success
    assert_equal "campsend", json.dig("result", "serverInfo", "name")
    assert json.dig("result", "capabilities", "tools")

    post mcp_server_path,
      params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{@raw_token}" }

    # A notification has no id, so there is nothing to answer with.
    assert_response :accepted
    assert_empty response.body
  end

  test "tools/list advertises both read tools as read-only" do
    call("tools/list")

    assert_response :success
    names = json.dig("result", "tools").map { |tool| tool["name"] }
    assert_equal %w[get_delivery list_deliveries], names.sort
    json.dig("result", "tools").each do |tool|
      assert tool.dig("annotations", "readOnlyHint"), "#{tool["name"]} must declare it does not mutate"
    end
  end

  test "list_deliveries returns the caller's deliveries and nobody else's" do
    mine = create_delivery(@user, "them@example.com")
    other = User.create!(email_address: "other@example.com")
    create_delivery(other, "someone@example.com")

    call("tools/call", params: { name: "list_deliveries", arguments: {} })

    assert_response :success
    deliveries = structured.fetch("deliveries")
    assert_equal 1, deliveries.size
    assert_equal mine.delivery_identifier, deliveries.first["delivery_identifier"]
    assert_equal "them@example.com", deliveries.first["recipient_email"]
  end

  test "list_deliveries clamps the limit and filters by status" do
    3.times { |i| create_delivery(@user, "them#{i}@example.com") }

    call("tools/call", params: { name: "list_deliveries", arguments: { limit: 1 } })
    assert_equal 1, structured.fetch("deliveries").size

    call("tools/call", params: { name: "list_deliveries", arguments: { limit: 5_000 } })
    assert_equal 3, structured.fetch("deliveries").size

    call("tools/call", params: { name: "list_deliveries", arguments: { status: "canceled" } })
    assert_empty structured.fetch("deliveries")
  end

  test "get_delivery returns events and files by slug or public id" do
    delivery = create_delivery(@user, "them@example.com", slug: "final-contract")
    delivery.record_event!("opened")

    call("tools/call", params: { name: "get_delivery", arguments: { delivery_identifier: "final-contract" } })

    assert_response :success
    assert_equal "final-contract", structured["delivery_identifier"]
    assert_equal [ "sent", "opened" ], structured["events"].map { |event| event["type"] }
    assert_equal 1, structured["files"].size
    assert_equal "contract.txt", structured["files"].first["filename"]

    call("tools/call", params: { name: "get_delivery", arguments: { delivery_identifier: delivery.public_id } })
    assert_equal "final-contract", structured["delivery_identifier"]
  end

  test "another user's delivery is not found rather than forbidden" do
    other = User.create!(email_address: "other@example.com")
    theirs = create_delivery(other, "someone@example.com")

    call("tools/call", params: { name: "get_delivery", arguments: { delivery_identifier: theirs.public_id } })

    assert_response :success
    assert json.dig("result", "isError"), "a delivery the caller does not own must be an error"
    assert_match(/No delivery/, json.dig("result", "content", 0, "text"))
  end

  test "tool output carries no access token, digest or signed URL" do
    delivery = create_delivery(@user, "them@example.com")
    raw_access = delivery.issue_access_token!

    call("tools/call", params: { name: "get_delivery", arguments: { delivery_identifier: delivery.public_id } })

    assert_response :success
    assert_no_match Regexp.new(Regexp.escape(raw_access)), response.body
    assert_no_match Regexp.new(Regexp.escape(delivery.reload.access_token_digest)), response.body
    assert_no_match(/rails\/active_storage/, response.body)
  end

  test "every call emits one wide event naming the tool and the token" do
    create_delivery(@user, "them@example.com")
    token = ApiToken.order(:id).last

    events = capture_wide_events do
      call("tools/call", params: { name: "list_deliveries", arguments: {} })
    end
    event = events.find { |candidate| candidate["mcp_method"] }

    assert_equal "tools/call", event["mcp_method"]
    assert_equal token.id, event["api_token_id"]
    assert_equal @user.id, event["user_id"]
    assert_equal "ok", event["mcp_outcome"]
  end

  test "using a token records it without rewriting on every call" do
    token = ApiToken.order(:id).last
    assert_nil token.last_used_at

    call("tools/list")

    assert_not_nil token.reload.last_used_at
  end

  private
    def call(method, params: nil, token: :default)
      raw = token == :default ? @raw_token : token
      headers = { "CONTENT_TYPE" => "application/json" }
      headers["Authorization"] = "Bearer #{raw}" if raw
      body = { jsonrpc: "2.0", id: 1, method: method }
      body[:params] = params if params
      post mcp_server_path, params: body.to_json, headers: headers
    end

    def json
      @json = JSON.parse(response.body)
    end

    def structured
      json.dig("result", "structuredContent")
    end

    def create_delivery(user, recipient, slug: nil)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("contract"), filename: "contract.txt", content_type: "text/plain")
      blob.update!(uploader_id: user.id)
      delivery = user.sends.new(recipient_email: recipient, message: "Here you go.", slug: slug, files: [ blob ])
      delivery.issue_access_token
      delivery.save!
      delivery.record_event!("sent")
      delivery
    end

    def capture_wide_events
      output = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(output))
      yield
      Rails.logger = original
      output.rewind
      output.read.lines.filter_map do |line|
        JSON.parse(line.sub(/\A\[[^\]]*\] /, ""))
      rescue JSON::ParserError
        nil
      end
    ensure
      Rails.logger = original
    end
end
