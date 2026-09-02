require "test_helper"

class CampsendPolicyTest < ActiveSupport::TestCase
  test "default policy admits storage and deliveries" do
    policy = Campsend::Policy.new

    assert_equal :stored, policy.admit_storage(user: Object.new, byte_size: 1) { :stored }
    assert_equal :sent, policy.admit_delivery(user: Object.new) { :sent }
  end

  test "default policy has no usage UI or extra telemetry" do
    policy = Campsend::Policy.new

    assert_nil policy.usage_for(Object.new)
    assert_empty policy.telemetry_for(Object.new)
  end

  test "denial exposes a safe outcome and message" do
    error = Campsend::Policy::Denied.new("Limit reached.", outcome: "limit")

    assert_equal "limit", error.outcome
    assert_equal "Limit reached.", error.message
  end

  test "the base policy leaves the delivery size ungated" do
    user = User.create!(email_address: "sender@example.com")

    # A self-hosted install keeps whatever Send::MAX_SEND_SIZE says, and the
    # policy is the seam a paid distribution raises it through.
    assert_equal Send::MAX_SEND_SIZE, Campsend::Policy.new.max_send_size_for(user)
    assert_equal Send::MAX_SEND_SIZE, Send.max_size_for(user)
  end

  test "a raised limit reaches every size check, and the messages say the real number" do
    user = User.create!(email_address: "sender@example.com")
    raised = Campsend::Policy.new
    raised.define_singleton_method(:max_send_size_for) { |_user| 9.gigabytes }

    with_policy(raised) do
      assert_equal 9.gigabytes, Send.max_size_for(user)
      assert_equal "9 GB", Send.human_max_size_for(user)

      # The upload gate is the first thing a large file meets.
      blob = user.reserve_blob!(filename: "master.mov", byte_size: 5.gigabytes,
        checksum: Digest::MD5.base64digest("x"), content_type: "video/quicktime")

      assert blob.persisted?, "a 5 GB reservation must succeed once the policy allows 9 GB"
    end
  end

  test "an oversized upload names the caller's own limit" do
    user = User.create!(email_address: "sender@example.com")

    error = assert_raises(User::UploadTooLarge) do
      user.reserve_blob!(filename: "master.mov", byte_size: Send::MAX_SEND_SIZE + 1,
        checksum: Digest::MD5.base64digest("x"), content_type: "video/quicktime")
    end

    # Not a hardcoded "2 GB": the number has to follow the policy.
    assert_equal "File exceeds Campsend's #{Send.human_max_size_for(user)} limit.", error.message
  end

  private
    def with_policy(policy)
      original = Campsend.policy
      Campsend.policy = policy
      yield
    ensure
      Campsend.policy = original
    end
end
