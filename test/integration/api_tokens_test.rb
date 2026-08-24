require "test_helper"

class ApiTokensTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    sign_in_as(@user)
  end

  test "a token is shown once at creation and never again" do
    post api_tokens_path, params: { api_token: { name: "Claude", scope: "read" } }

    assert_response :created
    raw = css_select(".token-reveal__value code").first.text
    assert raw.start_with?(ApiToken::PREFIX)
    assert_equal ApiToken.last, ApiToken.authenticate(raw)

    # The secret must not survive into the session, so it can't ride the flash.
    assert_nil session[:flash]

    get api_tokens_path

    assert_response :success
    assert_select ".token-reveal", count: 0
    assert_no_match Regexp.new(Regexp.escape(raw)), response.body
  end

  test "revoking hides the token and stops it authenticating" do
    post api_tokens_path, params: { api_token: { name: "Claude", scope: "write" } }
    raw = css_select(".token-reveal__value code").first.text
    token = ApiToken.last

    delete api_token_path(token)

    assert_redirected_to api_tokens_path
    assert_nil ApiToken.authenticate(raw)
    follow_redirect!
    assert_select ".token-list", count: 0
  end

  test "a token belonging to someone else is not found" do
    other = User.create!(email_address: "other@example.com")
    token, = ApiToken.issue_for(other, name: "Theirs", scope: "read")

    delete api_token_path(token)

    # Not found rather than forbidden, so a token id can't be probed for existence.
    assert_response :not_found
    assert token.reload.active?
  end

  test "the index lists only this user's live tokens" do
    ApiToken.issue_for(@user, name: "Mine", scope: "read")
    revoked, = ApiToken.issue_for(@user, name: "Old", scope: "read")
    revoked.revoke!
    other = User.create!(email_address: "other@example.com")
    ApiToken.issue_for(other, name: "Theirs", scope: "read")

    get api_tokens_path

    assert_response :success
    assert_select ".token-list tbody tr", count: 1
    assert_select ".token-list tbody th", text: "Mine"
  end

  test "creation errors render inline without losing the page" do
    post api_tokens_path, params: { api_token: { name: "", scope: "read" } }

    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /Name can't be blank/
    assert_select ".token-reveal", count: 0
  end

  test "a user cannot hold more than the maximum" do
    ApiToken::MAX_PER_USER.times { |i| ApiToken.issue_for(@user, name: "Token #{i}", scope: "read") }

    assert_no_difference "ApiToken.count" do
      post api_tokens_path, params: { api_token: { name: "One more", scope: "read" } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-errors", text: /Revoke one first/
  end

  test "tokens require a signed-in user" do
    delete session_path

    get api_tokens_path

    assert_redirected_to new_session_path
  end

  test "the raw token never reaches the logs" do
    output = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(output))
    post api_tokens_path, params: { api_token: { name: "Claude", scope: "read" } }
    Rails.logger = original

    raw = css_select(".token-reveal__value code").first.text
    output.rewind
    assert_no_match Regexp.new(Regexp.escape(raw)), output.read
  ensure
    Rails.logger = original
  end

  private
    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end
end
