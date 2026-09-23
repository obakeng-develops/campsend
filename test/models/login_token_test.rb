require "test_helper"

class LoginTokenTest < ActiveSupport::TestCase
  test "tokens work once" do
    user = User.create!(email_address: "sender@example.com")
    token, raw_token = LoginToken.issue_for(user)

    assert_equal user, LoginToken.consume(token.public_id, raw_token)
    assert_nil LoginToken.consume(token.public_id, raw_token)
  end

  test "a confirmation link lives a week, a sign-in link fifteen minutes" do
    user = User.create!(email_address: "sender@example.com")
    delivery = user.sends.new(recipient_email: "sam@example.com")
    delivery.files.attach(create_uploaded_blob(user))
    delivery.save!

    sign_in, = LoginToken.issue_for(user)
    confirm, = LoginToken.issue_for(user, intent: "send", delivery: delivery)

    assert_in_delta 15.minutes.from_now, sign_in.expires_at, 5
    assert_in_delta 7.days.from_now, confirm.expires_at, 5
  end

  test "a token can name the delivery it confirms, and outlives the delivery" do
    user = User.create!(email_address: "sender@example.com")
    delivery = user.sends.new(recipient_email: "sam@example.com")
    delivery.files.attach(create_uploaded_blob(user))
    delivery.save!
    token, _raw_token = LoginToken.issue_for(user, intent: "send", delivery: delivery)

    assert_equal delivery, token.delivery

    delivery.destroy!
    assert_nil token.reload.delivery
  end

  test "expired tokens do not work" do
    user = User.create!(email_address: "sender@example.com")
    token, raw_token = LoginToken.issue_for(user)
    token.update!(expires_at: 1.minute.ago)

    assert_nil LoginToken.consume(token.public_id, raw_token)
  end
end
