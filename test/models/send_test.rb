require "test_helper"

class SendTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = User.create!(email_address: "sender@example.com")
  end

  test "strips email subaddressing from recipient email" do
    send_record = @user.sends.new(recipient_email: "sam+tag@example.com")
    send_record.issue_access_token
    send_record.files.attach(create_uploaded_blob(@user))
    send_record.save!

    assert_equal "sam@example.com", send_record.recipient_email
  end

  test "requires a recipient and file" do
    send_record = @user.sends.new
    send_record.issue_access_token

    assert_not send_record.valid?
    assert_includes send_record.errors[:recipient_email], "can't be blank"
    assert_includes send_record.errors[:base], "Choose at least one file."
  end

  test "deliver! holds a delivery for an unverified sender and emails a confirm link instead of the recipient" do
    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    blob = create_uploaded_blob(guest)
    held = guest.sends.new(recipient_email: "sam@example.com")
    held.files.attach(blob)

    assert_enqueued_with(job: AuthenticationEmailJob, args: [ guest, "send", nil, held ]) do
      assert_no_enqueued_jobs(only: DeliveryEmailJob) { assert held.deliver! }
    end

    assert held.reload.email_status_held?
    assert_equal "held", held.display_status
    assert_nil held.publication_enqueued_at
    assert_not guest.files.blobs.exists?(blob.id), "files are retained at confirmation, not at hold"
  end

  test "confirm! publishes a held delivery once and retains its files" do
    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    blob = create_uploaded_blob(guest)
    held = guest.sends.new(recipient_email: "sam@example.com")
    held.files.attach(blob)
    held.deliver!

    assert_enqueued_with(job: DeliveryEmailJob, args: [ held ]) { assert held.confirm! }

    assert held.reload.email_status_pending?
    assert guest.files.blobs.exists?(blob.id)
    assert_no_enqueued_jobs(only: DeliveryEmailJob) { assert_not held.confirm! }
  end

  test "an unconfirmed sender may send five files, a confirmed one twenty" do
    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    six = 6.times.map { |i| create_uploaded_blob(guest, filename: "file-#{i}.txt") }

    too_many = guest.sends.new(recipient_email: "sam@example.com", files: six)
    assert_not too_many.valid?
    assert_includes too_many.errors[:base], "Choose no more than 5 files."

    assert guest.sends.new(recipient_email: "sam@example.com", files: six.first(5)).valid?

    guest.verify!
    assert guest.sends.new(recipient_email: "sam@example.com", files: six).valid?
  end

  test "a verified sender's delivery is never held" do
    delivery = build_send

    assert_enqueued_with(job: DeliveryEmailJob) { assert delivery.deliver! }

    assert delivery.reload.email_status_pending?
  end

  test "status follows the furthest recipient event" do
    send_record = create_send
    send_record.record_event!(:sent)
    send_record.record_event!(:opened)
    send_record.record_event!(:downloaded)

    assert_equal "downloaded", send_record.status
    assert_equal 3, send_record.send_events.count
  end

  test "delivery access expires and can be revoked" do
    send_record = create_send
    send_record.record_event!(:sent)

    assert send_record.access_active?
    send_record.update!(access_expires_at: 1.minute.ago)
    assert_not send_record.access_active?

    send_record.issue_access_token!
    send_record.revoke_access!
    assert_not send_record.access_active?
  end

  test "normalizes and resolves an optional delivery slug" do
    send_record = create_send(slug: " Project-Update ")

    assert_equal "project-update", send_record.slug
    assert_equal "project-update", send_record.delivery_identifier
    assert_equal send_record, Send.find_by_delivery_identifier("project-update")
    assert_equal send_record, Send.find_by_delivery_identifier(send_record.public_id)
  end

  test "rejects unsafe reserved and duplicate slugs" do
    assert_not build_send(slug: "project update").valid?
    assert_not build_send(slug: "files").valid?

    create_send(slug: "project-update")
    duplicate = build_send(slug: "project-update")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "published slugs cannot change or be deleted" do
    send_record = create_send(slug: "project-update")
    send_record.record_event!(:sent)

    assert_not send_record.update(slug: "new-path")
    assert_includes send_record.errors[:slug], "cannot change after publication"
    assert_not send_record.destroy
    assert Send.exists?(send_record.id)
  end

  test "display status prioritizes email and access state" do
    send_record = create_send
    assert_equal "sending", send_record.display_status

    send_record.update!(email_status: "failed")
    assert_equal "failed", send_record.display_status

    send_record.record_event!(:sent)
    send_record.update!(access_expires_at: 1.minute.ago)
    assert_equal "expired", send_record.display_status

    send_record.revoke_access!
    assert_equal "revoked", send_record.display_status
  end

  test "rejects a direct-upload blob owned by another sender" do
    other_user = User.create!(email_address: "other@example.com")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("private"),
      filename: "private.txt",
      content_type: "text/plain"
    )
    blob.update!(uploader_id: other_user.id)

    send_record = @user.sends.new(recipient_email: "sam@example.com", files: [ blob ])
    send_record.issue_access_token

    assert_not send_record.valid?
    assert_includes send_record.errors[:base], "You can only send files you uploaded."
  end

  test "rejects an ownerless blob" do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("ownerless"),
      filename: "ownerless.txt",
      content_type: "text/plain"
    )
    send_record = @user.sends.new(recipient_email: "sam@example.com", files: [ blob ])

    assert_not send_record.valid?
    assert_includes send_record.errors[:base], "You can only send files you uploaded."
  end

  test "creates an immutable first revision" do
    send_record = create_send

    assert_equal [ 1 ], send_record.delivery_revisions.pluck(:number)
    assert_equal send_record.files.first.blob_id, send_record.delivery_revisions.first.files.first.blob_id
    assert_raises(ActiveRecord::ReadOnlyRecord) { send_record.files = [ create_uploaded_blob(@user) ] }
  end

  test "replacing a file preserves the previous revision" do
    send_record = create_send
    original_blob = send_record.files.first.blob
    replacement = create_uploaded_blob(@user, content: "updated", filename: "updated.txt")

    revision = send_record.replace_file!(send_record.files.first.id, replacement)

    assert_equal 2, revision.number
    assert_equal replacement.id, send_record.reload.files.first.blob_id
    assert_equal original_blob.id, send_record.delivery_revisions.find_by!(number: 1).files.first.blob_id
  end

  test "revision numbers are unique within a delivery" do
    send_record = create_send
    duplicate = send_record.delivery_revisions.build(number: 1, files: [ create_uploaded_blob(@user) ])

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:number], "has already been taken"
  end

  test "rejects a replacement owned by another sender" do
    send_record = create_send
    other_user = User.create!(email_address: "other@example.com")
    replacement = create_uploaded_blob(other_user)

    assert_no_difference "DeliveryRevision.count" do
      assert_raises(ActiveRecord::RecordInvalid) do
        send_record.replace_file!(send_record.files.first.id, replacement)
      end
    end
  end

  test "scheduled deliveries remain unpublished until their future time" do
    send_record = @user.sends.new(recipient_email: "sam@example.com", scheduled_at: 2.hours.from_now)
    send_record.files.attach(create_uploaded_blob(@user))

    assert send_record.save
    assert send_record.scheduled?
    assert_equal "scheduled", send_record.display_status
    assert_not send_record.access_active?
  end

  test "rejects a schedule in the past" do
    send_record = @user.sends.new(recipient_email: "sam@example.com", scheduled_at: 1.minute.ago)
    send_record.files.attach(create_uploaded_blob(@user))

    assert_not send_record.valid?
    assert_includes send_record.errors[:scheduled_at], "must be in the future"
  end

  test "sent events record publication time" do
    send_record = create_send
    published_at = Time.current.change(usec: 0)

    event = send_record.record_event!(:sent, occurred_at: published_at)

    assert_equal published_at, send_record.reload.published_at
    assert_equal published_at, event.occurred_at
    assert send_record.access_active?
  end

  test "canceling an unpublished delivery is durable" do
    send_record = @user.sends.new(recipient_email: "sam@example.com", scheduled_at: 2.hours.from_now)
    send_record.files.attach(create_uploaded_blob(@user))
    send_record.save!

    assert send_record.cancel!
    assert send_record.reload.canceled?
    assert_equal "canceled", send_record.display_status
    assert_not send_record.cancel!
  end

  private
    def build_send(slug: nil)
      send_record = @user.sends.new(recipient_email: "sam@example.com", slug:)
      send_record.issue_access_token
      send_record.files.attach(create_uploaded_blob(@user))
      send_record
    end

    def create_send(slug: nil)
      send_record = build_send(slug:)
      send_record.save!
      send_record
    end
end
