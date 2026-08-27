require "test_helper"

class AuditEventTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sender@example.com")
    Current.actor = @user
  end

  teardown { Current.reset }

  test "an event snapshots the actor, so a deleted user's actions stay readable" do
    AuditEvent.record!(action: "api_token.created")
    event = AuditEvent.last

    assert_equal "user", event.actor_type
    assert_equal @user.id, event.actor_id
    assert_equal "sender@example.com", event.actor_label

    @user.destroy

    assert_equal "sender@example.com", event.reload.actor_label
  end

  test "an event snapshots the target, so a deleted delivery still has a name" do
    delivery = create_delivery
    AuditEvent.record!(action: "delivery.canceled", target: delivery)
    event = AuditEvent.last

    assert_equal "Send", event.target_type
    assert_equal delivery.id, event.target_id
    assert_includes event.target_label, "them@example.com"

    delivery.update_columns(published_at: nil, slug: nil)
    delivery.destroy

    assert_includes event.reload.target_label, "them@example.com"
    assert_equal delivery.id, event.target_id
  end

  test "the table is append-only outside the retention sweep" do
    AuditEvent.record!(action: "api_token.created")
    event = AuditEvent.last

    assert_raises(AuditEvent::Immutable) { event.update!(action: "something.else") }
    assert_raises(AuditEvent::Immutable) { event.destroy }
    assert_equal "api_token.created", event.reload.action
  end

  test "the retention sweep removes only what is past the window" do
    AuditEvent.record!(action: "recent.thing")
    AuditEvent.record!(action: "old.thing", occurred_at: (AuditEvent::RETENTION + 1.day).ago)

    assert_difference("AuditEvent.count", -1) { AuditEvent.purge_expired! }
    assert_equal [ "recent.thing" ], AuditEvent.pluck(:action)
  end

  test "occurred_at and recorded_at are separate, because a job records late" do
    happened = 2.hours.ago
    AuditEvent.record!(action: "delivery.sent", occurred_at: happened)
    event = AuditEvent.last

    assert_in_delta happened, event.occurred_at, 1.second
    assert_operator event.recorded_at, :>, event.occurred_at
  end

  test "an actor can be a token, a recipient or nobody" do
    token, = ApiToken.issue_for(@user, name: "Agent", scope: "read")
    Current.actor = token
    AuditEvent.record!(action: "delivery.created")
    assert_equal [ "api_token", token.id, "Agent" ], AuditEvent.last.slice(:actor_type, :actor_id, :actor_label).values

    Current.actor = "them@example.com"
    AuditEvent.record!(action: "delivery.opened")
    assert_equal [ "recipient", nil, "them@example.com" ], AuditEvent.last.slice(:actor_type, :actor_id, :actor_label).values

    Current.reset
    AuditEvent.record!(action: "delivery.sent")
    assert_equal [ "system", nil, nil ], AuditEvent.last.slice(:actor_type, :actor_id, :actor_label).values
  end

  test "outcome is constrained to succeeded or denied" do
    assert_raises(ActiveRecord::RecordInvalid) { AuditEvent.record!(action: "x", outcome: "maybe") }
  end

  private
    def create_delivery
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "c.txt", content_type: "text/plain")
      blob.update!(uploader_id: @user.id)
      delivery = @user.sends.new(recipient_email: "them@example.com", message: "Hi.", files: [ blob ])
      delivery.issue_access_token
      delivery.save!
      delivery
    end
end
