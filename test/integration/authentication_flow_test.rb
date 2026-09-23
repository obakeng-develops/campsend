require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  test "sender signs in with a single-use link" do
    user = User.create!(email_address: "sender@example.com")
    login_token, raw_token = LoginToken.issue_for(user)

    get sign_in_path(public_id: login_token.public_id)
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert login_token.reload.usable?
    assert_select "[data-secret-fragment-target='message'][hidden]", text: /link is incomplete/

    post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    assert_redirected_to files_path
    follow_redirect!
    assert_response :success

    delete session_path
    assert_redirected_to root_path
    follow_redirect!
    assert_redirected_to new_session_path
    follow_redirect!
    assert_response :success
    assert_select "h1", text: "Sign in or start free."
    assert_select ".auth-feedback", count: 0

    post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    assert_redirected_to new_session_path
  end

  test "self-hosted mode starts at sign-in and has no pricing page" do
    get root_path
    assert_redirected_to new_session_path

    get "/pricing"
    assert_response :not_found
  end

  test "protected pages redirect without redundant sign-in feedback" do
    get files_path

    assert_redirected_to new_session_path
    follow_redirect!
    assert_select ".flash-stack", count: 0
    assert_select ".auth-feedback", count: 0
  end

  test "sign-in errors appear inside the auth card" do
    post session_path, params: { email_address: "not-an-email" }

    assert_response :unprocessable_content
    assert_select ".auth-card .auth-feedback--alert[role='alert']", text: "Enter a valid email address."
    assert_select ".flash-stack", count: 0
  end

  test "expired sign-in links explain the error inside the auth card" do
    user = User.create!(email_address: "sender@example.com")
    login_token, = LoginToken.issue_for(user)
    login_token.update!(expires_at: 1.minute.ago)

    get sign_in_path(public_id: login_token.public_id)
    assert_redirected_to new_session_path
    follow_redirect!

    assert_select ".auth-card .auth-feedback--alert", text: "That sign-in link has expired. Ask for a new one."
  end

  test "requesting a link creates a sender and queues email" do
    assert_enqueued_with(job: AuthenticationEmailJob) do
      post session_path, params: { email_address: "New@Example.com" }
    end

    assert_redirected_to new_session_path
    assert_equal "new@example.com", User.last.email_address
    follow_redirect!
    assert_select "h1", text: "Check your inbox."
    assert_select ".auth-copy", text: /new@example.com/
    assert_select "form", count: 0
    # The only way onward is the inbox. A button here reads as the next step
    # on a phone and gets tapped, which requests a second link.
    assert_select ".button", count: 0
    assert_select ".fine-print a", text: "Use another email"

    get new_session_path
    assert_select "h1", text: "Check your inbox."
    get new_session_path(change_email: 1)
    assert_select "h1", text: "Sign in or start free."
  end

  test "sign-in returns you to where you started" do
    # The form has to carry it through its own POST, or it is lost before the
    # email is even sent.
    get new_session_path(return_to: "/pricing#studio")

    assert_select "input[type=hidden][name=return_to][value='/pricing#studio']", count: 1

    post session_path, params: { email_address: "sender@example.com", return_to: "/pricing#studio" }

    assert_redirected_to new_session_path(return_to: "/pricing#studio")
    assert_enqueued_with job: AuthenticationEmailJob, args: [ User.last, nil, "/pricing#studio" ]

    # And the check-your-inbox screen has to keep it, or changing your mind
    # about the address drops it.
    get new_session_path(return_to: "/pricing#studio")

    assert_select "a[href=?]", new_session_path(return_to: "/pricing#studio", change_email: 1)

    token, raw = LoginToken.issue_for(User.last, return_to: "/pricing#studio")
    post consume_sign_in_path(public_id: token.public_id), params: { token: raw }

    assert_redirected_to "/pricing#studio"
  end

  test "a return_to that is not a path on this site never reaches the token" do
    hostile = [ "https://example.com/phish", "//example.com/phish", "/\\example.com", "javascript:alert(1)", "pricing" ]

    hostile.each do |candidate|
      post session_path, params: { email_address: "sender@example.com", return_to: candidate }

      assert_enqueued_with job: AuthenticationEmailJob, args: [ User.last, nil, nil ]
    end

    hostile.each do |candidate|
      token = LoginToken.new(user: User.last, return_to: candidate, token_digest: "x", expires_at: 1.hour.from_now)

      assert token.invalid?, "#{candidate} must not be storable"
      assert_includes token.errors.attribute_names, :return_to
    end
  end

  test "return_to wins over the send intent, because it is the more specific answer" do
    user = User.create!(email_address: "sender@example.com")
    token, raw = LoginToken.issue_for(user, intent: "send", return_to: "/pricing")

    post consume_sign_in_path(public_id: token.public_id), params: { token: raw }

    assert_redirected_to "/pricing"
  end

  test "a signed-in visitor who lands on sign-in is sent where they were going" do
    sign_in_as User.create!(email_address: "sender@example.com")

    get new_session_path(return_to: "/pricing")

    assert_redirected_to "/pricing"
  end

  test "send intent survives the sign-in link" do
    user = User.create!(email_address: "sender@example.com")
    login_token, raw_token = LoginToken.issue_for(user, intent: "send")

    post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }

    assert_redirected_to new_send_path
  end

  test "a new sender who wants to send starts as a guest, without an email" do
    assert_no_enqueued_jobs only: AuthenticationEmailJob do
      start_guest_as "guest@example.com"
    end

    assert_redirected_to new_send_path
    assert session[:guest]
    guest = User.last
    assert_equal "guest@example.com", guest.email_address
    assert_not guest.verified?

    follow_redirect!
    assert_response :success
    assert_select "body.guest-body"
    assert_select ".site-sidebar", count: 0
    assert_select "a.back-link", count: 0
  end

  test "anyone may open the composer, and the address they give there starts a guest session" do
    get new_send_path

    assert_response :success
    assert_select "body.guest-body"
    assert_select "main.app-main"
    assert_select "input[name='sender_email'][required][data-start-url=?]", session_path
    assert_select "input[type='file']"

    post session_path, params: { email_address: "guest@example.com", intent: "send" }, as: :json

    assert_response :no_content
    assert session[:guest]
    assert_equal User.last.id, session[:user_id]

    post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    assert_response :success
    get new_send_path
    assert_select "input[name='sender_email']", count: 0
  end

  test "a claimed address given in the composer is sent to the sign-in page" do
    User.create!(email_address: "sender@example.com")

    post session_path, params: { email_address: "sender@example.com", intent: "send" }, as: :json

    assert_response :success
    assert_equal new_session_path(intent: "send"), response.parsed_body.fetch("location")
    assert_nil session[:user_id]

    post session_path, params: { email_address: "not-an-email", intent: "send" }, as: :json
    assert_response :unprocessable_content
    assert_equal "Enter a valid email address.", response.parsed_body.fetch("error")
  end

  test "sending from the composer without a session goes to sign-in" do
    post sends_path, params: { send: { recipient_email: "sam@example.com" } }

    assert_redirected_to new_session_path
  end

  test "a claimed address never gets a guest session" do
    User.create!(email_address: "sender@example.com")

    assert_enqueued_with(job: AuthenticationEmailJob) { start_guest_as "sender@example.com" }

    assert_redirected_to new_session_path(intent: "send")
    assert_nil session[:user_id]
    follow_redirect!
    assert_select "h1", text: "Check your inbox."
    assert_select ".auth-copy", text: /continue your delivery/
  end

  test "an address with a held delivery never gets a second guest session" do
    start_guest_as "guest@example.com"
    guest = User.last
    held = guest.sends.new(recipient_email: "sam@example.com")
    held.files.attach(create_uploaded_blob(guest))
    held.deliver!

    open_session do |stranger|
      stranger.post session_path, params: { email_address: "guest@example.com", intent: "send" }

      stranger.assert_redirected_to new_session_path(intent: "send")
      stranger.get send_path(held)
      stranger.assert_redirected_to new_session_path
    end
  end

  test "a guest is bounced from verified-only pages, and the sign-in page does not bounce them back" do
    start_guest_as "guest@example.com"

    get files_path
    assert_redirected_to new_session_path
    get api_tokens_path
    assert_redirected_to new_session_path

    get new_session_path
    assert_response :success
    assert_select "h1", text: "Sign in or start free."
  end

  test "a guest session ends the moment the address is confirmed anywhere" do
    start_guest_as "guest@example.com"
    guest = User.last

    open_session do |phone|
      login_token, raw_token = LoginToken.issue_for(guest)
      phone.post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
      phone.assert_redirected_to files_path
    end

    get new_send_path
    assert_select "input[name='sender_email']", count: 1, message: "the composer asks for an address again"
    post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    assert_response :unauthorized
  end

  test "consuming a sign-in link verifies the sender" do
    user = User.create_with(verified_at: nil).find_or_create_by!(email_address: "sender@example.com")

    sign_in_as(user)

    assert user.reload.verified?
    get files_path
    assert_response :success
  end

  test "pending sign-in copy follows the issued link intent" do
    post session_path, params: { email_address: "sender@example.com" }

    get new_session_path(intent: "send")

    assert_select ".auth-copy", text: /continue your delivery/, count: 0
  end

  test "direct upload grants require a signed-in sender" do
    post rails_direct_uploads_path, params: { blob: blob_params }, as: :json

    assert_response :unauthorized
    assert_equal "Sign in to upload files.", response.parsed_body.fetch("error")
    assert_not ActiveStorage::Blob.exists?
  end

  test "a guest may reserve a direct upload" do
    start_guest_as "guest@example.com"

    post rails_direct_uploads_path, params: { blob: blob_params }, as: :json

    assert_response :success
    assert_equal User.last.id, ActiveStorage::Blob.last.uploader_id
  end

  test "direct upload grants reject an expired sender session" do
    user = User.create!(email_address: "sender@example.com")
    sign_in_as(user)

    travel Authentication::SESSION_LIFETIME + 1.minute do
      post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    end

    assert_response :unauthorized
    assert_not ActiveStorage::Blob.exists?
  end

  test "oversized direct uploads are rejected" do
    user = User.create!(email_address: "sender@example.com")
    sign_in_as(user)

    post rails_direct_uploads_path, params: {
      blob: blob_params.merge(byte_size: Send::MAX_SEND_SIZE + 1)
    }, as: :json

    assert_response :content_too_large
    assert_equal "File exceeds Campsend's 2 GB limit.", response.parsed_body.fetch("error")
    assert_not ActiveStorage::Blob.exists?
  end

  test "self-hosted accounts do not have aggregate storage quotas" do
    user = User.create!(email_address: "sender@example.com")
    reserve_storage(user, 2.gigabytes)
    sign_in_as(user)

    assert_difference "ActiveStorage::Blob.count", 1 do
      post rails_direct_uploads_path, params: { blob: blob_params }, as: :json
    end
    assert_response :success
  end

  test "the sign-in page never renders the shell of an already signed-in user" do
    signed_in = User.create!(email_address: "signed-in@example.com")
    other = User.create!(email_address: "other@example.com")
    sign_in_as(signed_in)

    login_token, _raw = LoginToken.issue_for(other)
    get sign_in_path(public_id: login_token.public_id)

    assert_response :success
    assert_select "body.guest-body"
    assert_select ".site-sidebar", count: 0
    assert_select "body.app-body", count: 0
  end

  test "a delivery page never wears the shell of the account viewing it" do
    sender = User.create!(email_address: "sender-shell@example.com")
    sign_in_as(sender)
    send = sender.sends.new(recipient_email: "alex@example.com", message: "Hello")
    send.issue_access_token
    send.files.attach(create_uploaded_blob(sender, filename: "sample.txt"))
    send.save!
    send.record_event!(:sent)

    get delivery_path(public_id: send.public_id)

    assert_response :success
    assert_select "body.guest-body"
    assert_select ".site-sidebar", count: 0
  end

  private
    def reserve_storage(user, byte_size)
      ActiveStorage::Blob.create_before_direct_upload!(
        filename: "reserved.bin",
        byte_size: byte_size,
        checksum: Base64.strict_encode64(Digest::MD5.digest("reserved")),
        content_type: "application/octet-stream"
      ).update!(uploader_id: user.id)
    end
end
