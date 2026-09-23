require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "strips email subaddressing so +tags cannot create duplicate accounts" do
    user = User.create!(email_address: "sender+tag@example.com")
    assert_equal "sender@example.com", user.email_address

    duplicate = User.find_or_create_by!(email_address: "sender+other@example.com")
    assert_equal user.id, duplicate.id
  end

  test "a user is verified by default, and only a sign-in request creates one who is not" do
    assert User.create!(email_address: "sender@example.com").verified?

    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    assert_not guest.verified?

    guest.verify!
    assert guest.reload.verified?
  end

  test "guest eligibility ends with verification or a first delivery" do
    guest = User.create_with(verified_at: nil).find_or_create_by!(email_address: "guest@example.com")
    assert guest.guest_eligible?

    held = guest.sends.new(recipient_email: "sam@example.com")
    held.files.attach(create_uploaded_blob(guest))
    held.save!
    assert_not guest.guest_eligible?

    assert_not User.create!(email_address: "sender@example.com").guest_eligible?
  end

  test "blob reservations enforce the file size limit" do
    user = User.create!(email_address: "sender@example.com")

    error = assert_raises(User::UploadTooLarge) do
      user.reserve_blob!(byte_size: Send::MAX_SEND_SIZE + 1)
    end

    assert_equal "File exceeds Campsend's 2 GB limit.", error.message
    assert_not user.uploaded_blobs.exists?
  end

  test "blob reservations reject negative sizes" do
    user = User.create!(email_address: "sender@example.com")

    error = assert_raises(User::InvalidUploadSize) { user.reserve_blob!(byte_size: -1) }

    assert_equal "File size cannot be negative.", error.message
    assert_not user.uploaded_blobs.exists?
  end

  test "blob reservations use the policy storage service" do
    user = User.create!(email_address: "sender@example.com")
    policy = Class.new(Campsend::Policy) do
      def storage_service_name_for(user:)
        "alternate_test"
      end

      def storage_key_prefix_for(user:)
        "accounts/#{user.id}/files"
      end
    end.new
    original_policy = Campsend.policy
    Campsend.policy = policy

    blob = user.reserve_blob!(
      filename: "hello.txt",
      byte_size: 5,
      checksum: Base64.strict_encode64(Digest::MD5.digest("hello")),
      content_type: "text/plain"
    )

    assert_equal "alternate_test", blob.service_name
    assert blob.key.start_with?("accounts/#{user.id}/files/")
    assert_equal user.id, blob.uploader_id
  ensure
    Campsend.policy = original_policy
  end
end
