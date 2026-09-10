require "test_helper"

class MailerCopyTest < ActionMailer::TestCase
  test "sign-in email explains its single-use link" do
    user = User.create!(email_address: "sender@example.com")
    login_token, raw_token = LoginToken.issue_for(user)
    mail = AuthenticationMailer.with(login_token: login_token, token: raw_token).sign_in

    assert_equal "Your Campsend sign-in link", mail.subject
    assert_includes mail.text_part.body.decoded, "Click the link below to sign in. This single-use link expires in 15 minutes:"
    assert_includes mail.text_part.body.decoded, "Didn’t request this? You can safely ignore this email."
  end

  test "delivery email names one file and explains forwarding" do
    sender = User.create!(email_address: "sender@example.com")
    delivery = sender.sends.new(recipient_email: "sam@example.com", files: [ create_uploaded_blob(sender) ])
    token = delivery.issue_access_token
    delivery.save!
    mail = DeliveryMailer.with(send: delivery, access_token: token).files_ready

    assert_equal "Your file is ready", mail.subject
    # The sender's address identifies them in the display name and Reply-To.
    # Putting it in the subject is what made these look like phishing.
    assert_equal [ "sender@example.com" ], mail.reply_to
    assert_match(/\Asender@example\.com via /, mail[:from].display_names.first)
    assert_not_includes mail.subject, "sender@example.com"
    # Attribution stays, but the body no longer opens on a bare address either.
    assert_match(/\AYour file is ready\./, mail.text_part.body.decoded.strip)
    assert_includes mail.text_part.body.decoded, "sender@example.com sent it to you."
    assert_includes mail.text_part.body.decoded, "View file:"
    assert_includes mail.text_part.body.decoded, "Forwarding the full link shares access."
  end

  test "delivery email pluralizes multiple files" do
    sender = User.create!(email_address: "sender@example.com")
    delivery = sender.sends.new(
      recipient_email: "sam@example.com",
      files: [ create_uploaded_blob(sender), create_uploaded_blob(sender, filename: "second.txt") ]
    )
    token = delivery.issue_access_token
    delivery.save!
    mail = DeliveryMailer.with(send: delivery, access_token: token).files_ready

    assert_equal "Your 2 files are ready", mail.subject
    assert_includes mail.text_part.body.decoded, "View files:"
  end

  test "delivery email uses a sender-chosen slug" do
    sender = User.create!(email_address: "sender@example.com")
    delivery = sender.sends.new(recipient_email: "sam@example.com", slug: "client-files", files: [ create_uploaded_blob(sender) ])
    token = delivery.issue_access_token
    delivery.save!

    mail = DeliveryMailer.with(send: delivery, access_token: token).files_ready

    assert_includes mail.text_part.body.decoded, "/d/client-files#token="
  end
end
