require "test_helper"

class SecurityCleanupJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sender@example.com")
    @service = ActiveStorage::Blob.services.fetch("s3_test")
    @requests_before = @service.client.client.api_requests.size
  end

  test "an abandoned upload is aborted, then the blob that reserved it is purged" do
    blob = travel_to(3.days.ago) { reserve }
    @service.client.client.stub_responses(:list_multipart_uploads, {
      uploads: [ { key: blob.key, upload_id: "u1", initiated: 3.days.ago } ], is_truncated: false
    })
    @service.client.client.stub_responses(:abort_multipart_upload, {})

    with_s3 { SecurityCleanupJob.perform_now }

    assert_equal [ blob.key ], operations(:abort_multipart_upload)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_operator sequence.index(:abort_multipart_upload), :<, sequence.index(:delete_object),
      "aborting has to happen before the purge, or a completion racing the job outlives it"
  end

  test "an upload still in flight is left alone, and so is its reservation" do
    blob = reserve
    @service.client.client.stub_responses(:list_multipart_uploads, {
      uploads: [ { key: blob.key, upload_id: "u1", initiated: 5.minutes.ago } ], is_truncated: false
    })

    with_s3 { SecurityCleanupJob.perform_now }

    assert_empty operations(:abort_multipart_upload)
    assert ActiveStorage::Blob.exists?(blob.id)
  end

  test "an unconfirmed sender and their held delivery are removed after a week, files included" do
    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    held_blob = create_uploaded_blob(guest)
    held = guest.sends.new(recipient_email: "sam@example.com")
    held.files.attach(held_blob)
    held.deliver!
    reserved = create_uploaded_blob(guest, filename: "never-sent.txt")
    recent = User.create_with(verified_at: nil).find_or_create_by!(email_address: "recent@example.com")
    verified_held = @user.sends.new(recipient_email: "sam@example.com")
    verified_held.files.attach(create_uploaded_blob(@user))
    verified_held.save!
    verified_held.update!(email_status: "held")

    travel 8.days do
      recent.update!(created_at: 1.day.ago)
      SecurityCleanupJob.perform_now
    end

    assert_not User.exists?(guest.id)
    assert_not Send.exists?(held.id)
    assert_not ActiveStorage::Blob.exists?(held_blob.id)
    assert_not ActiveStorage::Blob.exists?(reserved.id)
    assert User.exists?(recent.id), "a week has to pass first"
    assert_not Send.exists?(verified_held.id), "a held delivery is removed on age alone"
    assert User.exists?(@user.id), "a verified sender is never removed"
  end

  test "the job still runs where multipart is not supported" do
    stale = travel_to(3.days.ago) { create_uploaded_blob(@user) }

    SecurityCleanupJob.perform_now

    assert_not ActiveStorage::Blob.exists?(stale.id)
  end

  private
    def reserve
      ActiveStorage::Blob.create_before_direct_upload!(
        key: "users/#{@user.id}/blobs/#{ActiveStorage::Blob.generate_unique_secure_token}",
        filename: "master.mov", byte_size: 500.megabytes,
        checksum: Base64.strict_encode64(Digest::MD5.digest("x")),
        content_type: "video/quicktime", service_name: "s3_test"
      ).tap { |blob| blob.update!(uploader_id: @user.id) }
    end

    def with_s3
      previous = ActiveStorage::Blob.service
      ActiveStorage::Blob.service = @service
      yield
    ensure
      ActiveStorage::Blob.service = previous
    end

    def sequence
      @service.client.client.api_requests.drop(@requests_before).map { |request| request[:operation_name] }
    end

    def operations(name)
      @service.client.client.api_requests.drop(@requests_before)
              .select { |request| request[:operation_name] == name }
              .map { |request| request[:params][:key] }
    end
end
