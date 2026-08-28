require "test_helper"

class ActivityTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    sign_in_as(@user)
  end

  test "the page lists this account's events, newest first, in plain language" do
    create_delivery
    newer = create_delivery(publish: true)
    post revoke_access_send_path(newer)

    get activity_path

    assert_response :success
    headings = css_select(".activity-list > li strong").map(&:text)
    assert_equal "Revoked recipient access", headings.first, "newest first"
    assert_includes headings, "Created a delivery"
    # Dotted identifiers are the query language, not the reading language. They
    # belong in the filter's values and nowhere a customer reads.
    assert_empty css_select(".activity-list").to_s.scan(/delivery\.\w+/)
    assert_select ".activity-item__who", text: /sender@example\.com/
  end

  test "another account's events are not visible, and there is nothing to forbid" do
    other = User.create!(email_address: "other@example.com")
    Current.actor = other
    theirs = other.sends.new(recipient_email: "someone@example.com", message: "Hi.", files: [ blob_for(other) ])
    theirs.issue_access_token
    theirs.save!
    Current.reset

    get activity_path

    assert_response :success
    assert_select ".activity-list > li", count: 0
    assert_no_match(/someone@example\.com/, response.body)
  end

  test "filtering by action offers only what this account has done" do
    create_delivery
    post api_tokens_path, params: { api_token: { name: "Claude", scope: "read" } }

    get activity_path

    options = css_select(".activity-filters select option").map { |option| option["value"] }.compact_blank
    assert_includes options, "api_token.created"
    assert_not_includes options, "delivery.canceled", "an action nobody has taken would filter to nothing"

    get activity_path, params: { audit_action: "api_token.created" }

    assert_select ".activity-list > li", count: 1
    assert_select ".activity-list > li strong", text: "Created an API token"
  end

  test "filtering by date is inclusive of both ends" do
    delivery = create_delivery
    AuditEvent.where(target_id: delivery.id).update_all(occurred_at: 3.days.ago)

    get activity_path, params: { from: 3.days.ago.to_date.to_s, to: 3.days.ago.to_date.to_s }
    assert_select ".activity-list > li", minimum: 1

    get activity_path, params: { from: 2.days.ago.to_date.to_s }
    assert_select ".activity-list > li", count: 0
  end

  test "a malformed date is ignored rather than raising" do
    create_delivery

    get activity_path, params: { from: "not-a-date", to: "" }

    assert_response :success
    assert_select ".activity-list > li", minimum: 1
  end

  test "a recipient's actions appear in the sender's log" do
    delivery = create_delivery(publish: true)
    raw = delivery.reload.issue_access_token!
    delete session_path
    post delivery_access_path(public_id: delivery.public_id), params: { token: raw }
    post delivery_opened_path(public_id: delivery.public_id)

    sign_in_as(@user)
    get activity_path

    assert_select ".activity-list > li strong", text: "Opened the delivery"
    # It is the sender's log, so the recipient is named as the actor.
    assert_select ".activity-item__who", text: /them@example\.com \(recipient\)/
  end

  test "a delivery page shows its own history" do
    delivery = create_delivery(publish: true)
    post revoke_access_send_path(delivery)

    get send_path(delivery)

    assert_response :success
    assert_select ".delivery-history .activity-list > li strong", text: "Revoked recipient access"
    assert_select ".delivery-history .activity-list > li strong", text: "Created a delivery"
  end

  test "history survives the delivery it describes" do
    delivery = create_delivery(publish: true)
    post revoke_access_send_path(delivery)

    get activity_path
    assert_select ".activity-list > li", minimum: 2

    delivery.update_columns(published_at: nil, slug: nil)
    delivery.destroy

    get activity_path

    assert_response :success
    assert_select ".activity-list > li", minimum: 2
    assert_match(/them@example\.com/, response.body, "the snapshot label outlives the record")
  end

  test "the page needs a session" do
    delete session_path

    get activity_path

    assert_redirected_to new_session_path
  end

  private
    def blob_for(user)
      ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "c.txt", content_type: "text/plain").tap do |blob|
        blob.update!(uploader_id: user.id)
      end
    end

    # Revoking needs a published delivery, and publication happens in the job.
    def create_delivery(publish: false)
      publish ? perform_enqueued_jobs { post_delivery } : post_delivery
      Send.last
    end

    def post_delivery
      post sends_path, params: { send: { recipient_email: "them@example.com", message: "Hi.", files: [ blob_for(@user).signed_id ] } }
    end

    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end
end
