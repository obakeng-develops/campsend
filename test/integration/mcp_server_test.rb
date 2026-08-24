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

  test "tools/list declares which tools mutate state" do
    call("tools/list")

    assert_response :success
    tools = json.dig("result", "tools").index_by { |tool| tool["name"] }
    assert_equal %w[create_delivery get_delivery list_deliveries], tools.keys.sort

    %w[list_deliveries get_delivery].each do |name|
      assert tools.dig(name, "annotations", "readOnlyHint"), "#{name} does not mutate and must say so"
      # The gem defaults destructiveHint to true, which would make a client warn
      # before a harmless call.
      assert_not tools.dig(name, "annotations", "destructiveHint"), "#{name} must not be flagged destructive"
    end

    assert_not tools.dig("create_delivery", "annotations", "readOnlyHint"), "create_delivery changes state and must say so"
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

  test "create_delivery needs a write token" do
    blob = owned_blob

    assert_no_difference "Send.count" do
      create(file_ids: [ blob.id ])
    end

    assert json.dig("result", "isError")
    assert_match(/write scope/, text_content)
  end

  test "create_delivery sends a delivery and returns it" do
    blob = owned_blob
    writer

    assert_difference [ "Send.count", "ActionMailer::Base.deliveries.size" ], 1 do
      perform_enqueued_jobs { create(file_ids: [ blob.id ], message: "Here you go.", slug: "final-contract") }
    end

    assert_response :success
    assert_not json.dig("result", "isError")
    assert_equal "final-contract", structured["delivery_identifier"]
    assert_equal "them@example.com", structured["recipient_email"]
    assert_equal 1, structured["files"].size

    delivery = Send.last
    assert_equal @user, delivery.user
    # retain_files runs, so the blob is in the sender's library afterwards.
    assert_includes @user.files.blobs.ids, blob.id
  end

  test "create_delivery accepts only blobs the caller owns" do
    other = User.create!(email_address: "other@example.com")
    theirs = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "theirs.txt", content_type: "text/plain")
    theirs.update!(uploader_id: other.id)
    writer

    assert_no_difference "Send.count" do
      create(file_ids: [ theirs.id ])
    end

    assert json.dig("result", "isError")
    assert_match(/not yours/, text_content)

    assert_no_difference "Send.count" do
      create(file_ids: [ owned_blob.id, theirs.id ])
    end

    assert json.dig("result", "isError")
  end

  test "create_delivery reports the model's own validation messages" do
    blob = owned_blob
    writer

    assert_no_difference "Send.count" do
      create(file_ids: [ blob.id ], recipient_email: "not-an-email")
    end
    assert_match(/Recipient email is invalid/, text_content)

    assert_no_difference "Send.count" do
      create(file_ids: [ blob.id ], slug: "files")
    end
    assert_match(/Slug is reserved/, text_content)

    assert_no_difference "Send.count" do
      create(file_ids: [ blob.id ], scheduled_at: 1.hour.ago.iso8601)
    end
    assert_match(/Scheduled at must be in the future/, text_content)
  end

  test "a policy denial creates nothing and carries the policy's own message" do
    blob = owned_blob
    writer
    denial = Campsend::Policy::Denied.new("Your Free plan includes 15 deliveries each month.", outcome: "delivery_limit")

    Campsend.policy.define_singleton_method(:admit_delivery) { |user:, &block| raise denial }
    begin
      assert_no_difference [ "Send.count", "ActionMailer::Base.deliveries.size" ] do
        create(file_ids: [ blob.id ])
      end
    ensure
      Campsend.policy.singleton_class.remove_method(:admit_delivery)
    end

    assert json.dig("result", "isError")
    assert_equal "Your Free plan includes 15 deliveries each month.", text_content
  end

  test "create_delivery refuses more files than a delivery allows" do
    writer
    blobs = (Send::MAX_FILES + 1).times.map { |i| owned_blob("file#{i}.txt") }

    assert_no_difference "Send.count" do
      create(file_ids: blobs.map(&:id))
    end

    assert json.dig("result", "isError")
  end

  private
    def writer
      _, @raw_token = ApiToken.issue_for(@user, name: "Writer", scope: "write")
    end

    def owned_blob(filename = "contract.txt")
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new("contract"), filename: filename, content_type: "text/plain").tap do |blob|
        blob.update!(uploader_id: @user.id)
      end
    end

    def create(recipient_email: "them@example.com", **arguments)
      call("tools/call", params: { name: "create_delivery", arguments: { recipient_email: recipient_email, **arguments } })
    end

    def text_content
      json.dig("result", "content", 0, "text")
    end

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
