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

  test "send intent explains and resumes the delivery flow" do
    post session_path, params: { email_address: "sender@example.com", intent: "send" }
    follow_redirect!

    assert_select "h1", text: "Check your inbox."
    assert_select ".auth-copy", text: /continue your delivery/

    login_token, = LoginToken.issue_for(User.last, intent: "send")
    get sign_in_path(public_id: login_token.public_id)
    assert_select "input[type='submit'][value='Continue your delivery']"
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
    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end

    def blob_params
      content = "hello"
      {
        filename: "hello.txt",
        byte_size: content.bytesize,
        checksum: Base64.strict_encode64(Digest::MD5.digest(content)),
        content_type: "text/plain"
      }
    end

    def reserve_storage(user, byte_size)
      ActiveStorage::Blob.create_before_direct_upload!(
        filename: "reserved.bin",
        byte_size: byte_size,
        checksum: Base64.strict_encode64(Digest::MD5.digest("reserved")),
        content_type: "application/octet-stream"
      ).update!(uploader_id: user.id)
    end
end
