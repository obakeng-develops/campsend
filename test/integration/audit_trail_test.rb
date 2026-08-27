require "test_helper"

class AuditTrailTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    sign_in_as(@user)
  end

  test "a delivery records who created it and joins to its wide event" do
    assert_difference "AuditEvent.count", 1 do
      create_delivery
    end

    event = AuditEvent.last
    assert_equal "delivery.created", event.action
    assert_equal "succeeded", event.outcome
    assert_equal [ "user", @user.id, "sender@example.com" ], event.slice(:actor_type, :actor_id, :actor_label).values
    assert_equal Send.last.id, event.target_id
    # The join to the wide event for the same action is the reason both exist.
    assert_match(/\A[0-9a-f-]{36}\z/, event.request_id)
  end

  test "a rolled back delivery leaves no row" do
    assert_no_difference "AuditEvent.count" do
      post sends_path, params: { send: { recipient_email: "not-an-email", message: "Hi.", files: [] } }
    end

    assert_response :unprocessable_entity
  end

  test "a policy denial is recorded with its reason and creates nothing" do
    denial = Campsend::Policy::Denied.new("Your Free plan includes 15 deliveries each month.", outcome: "delivery_limit")
    Campsend.policy.define_singleton_method(:admit_delivery) { |user:, &block| raise denial }

    begin
      assert_no_difference "Send.count" do
        assert_difference "AuditEvent.count", 1 do
          create_delivery
        end
      end
    ensure
      Campsend.policy.singleton_class.remove_method(:admit_delivery)
    end

    event = AuditEvent.last
    assert_equal "denied", event.outcome
    assert_equal "delivery_limit", event.denial_reason
    # The message is the customer's, not the log's. The reason is the queryable part.
    assert_nil event.target_id
  end

  test "a recipient opening is recorded as the recipient, not as the sender" do
    delivery = nil
    # A delivery is only reachable once the publication job has run, because that
    # is what stamps published_at.
    perform_enqueued_jobs { delivery = create_delivery }
    raw = delivery.reload.issue_access_token!
    AuditEvent.delete_all
    delete session_path

    post delivery_access_path(public_id: delivery.public_id), params: { token: raw }
    assert_response :redirect
    post delivery_opened_path(public_id: delivery.public_id)

    opened = AuditEvent.find_by(action: "delivery.opened")
    assert opened, "opening a delivery must be recorded"
    assert_equal "recipient", opened.actor_type
    assert_equal "them@example.com", opened.actor_label
    assert_nil opened.actor_id
  end

  test "revoking and rotating are recorded, with what moved" do
    delivery = nil
    perform_enqueued_jobs { delivery = create_delivery }
    AuditEvent.delete_all

    # rotate_access reissues the token inside a job rather than in the request,
    # so the row appears when the job runs.
    perform_enqueued_jobs { post rotate_access_send_path(delivery) }

    # Two rows: the person who asked, and the reissue the job performed. The
    # request is the one with an actor, because a job has no session.
    requested = AuditEvent.find_by(action: "delivery.access_rotation_requested")
    assert requested, "asking for a new link must be recorded"
    assert_equal [ "user", @user.id ], requested.slice(:actor_type, :actor_id).values

    rotated = AuditEvent.find_by(action: "delivery.access_rotated")
    assert rotated, "reissuing the token must be recorded"
    assert_equal 2, rotated.changed_fields["access_expires_at"].size

    post revoke_access_send_path(delivery)
    assert AuditEvent.exists?(action: "delivery.access_revoked", target_id: delivery.id)
  end

  test "tokens record their own creation and revocation, and never the secret" do
    post api_tokens_path, params: { api_token: { name: "Claude", scope: "write" } }
    raw = css_select(".token-reveal__value code").first.text
    created = AuditEvent.find_by(action: "api_token.created")

    assert created
    assert_equal "Claude", created.target_label
    assert_equal [ nil, "write" ], created.changed_fields["scope"]
    assert_no_match Regexp.new(Regexp.escape(raw)), AuditEvent.pluck(:action, :target_label, :changed_fields).to_s

    delete api_token_path(ApiToken.last)
    assert AuditEvent.exists?(action: "api_token.revoked")
  end

  test "nothing in the log carries an access token, a digest or a signed url" do
    delivery = create_delivery
    raw = delivery.reload.issue_access_token!
    post revoke_access_send_path(delivery)

    log = AuditEvent.all.map(&:attributes).to_s
    assert_no_match Regexp.new(Regexp.escape(raw)), log
    assert_no_match Regexp.new(Regexp.escape(delivery.reload.access_token_digest)), log
    assert_no_match(/rails\/active_storage/, log)
  end

  test "an MCP caller acts as its token, not as the user behind it" do
    _, token_raw = ApiToken.issue_for(@user, name: "Agent", scope: "write")
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "c.txt", content_type: "text/plain")
    blob.update!(uploader_id: @user.id)
    AuditEvent.delete_all

    post mcp_server_path,
      params: { jsonrpc: "2.0", id: 1, method: "tools/call",
                params: { name: "create_delivery", arguments: { recipient_email: "them@example.com", file_ids: [ blob.id ] } } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json", "Authorization" => "Bearer #{token_raw}" }

    event = AuditEvent.find_by(action: "delivery.created")
    assert event, "a delivery created over MCP must be recorded"
    # A revoked token's actions stay attributable to the token.
    assert_equal "api_token", event.actor_type
    assert_equal "Agent", event.actor_label
  end

  private
    def create_delivery
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "c.txt", content_type: "text/plain")
      blob.update!(uploader_id: @user.id)
      post sends_path, params: { send: { recipient_email: "them@example.com", message: "Hi.", files: [ blob.signed_id ] } }
      Send.last
    end

    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end
end
