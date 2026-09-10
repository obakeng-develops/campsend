require "test_helper"

class OauthSignInTest < ActionDispatch::IntegrationTest
  CREDENTIALS = {
    "GOOGLE_OAUTH_CLIENT_ID" => "google-id",
    "GOOGLE_OAUTH_CLIENT_SECRET" => "google-secret",
    "GITHUB_OAUTH_CLIENT_ID" => "github-id",
    "GITHUB_OAUTH_CLIENT_SECRET" => "github-secret"
  }.freeze

  test "a provider with no credentials does not exist" do
    assert_empty OauthProvider.configured
    assert_nil OauthProvider.find("google")

    get new_session_path

    assert_response :success
    assert_select ".auth-providers", count: 0
    # The email form is still the whole of sign-in for a self-hoster.
    assert_select "form[action=?]", session_path
  end

  test "configured providers are offered above the email form" do
    with_oauth do
      get new_session_path

      assert_response :success
      assert_select ".auth-providers form[action=?]", oauth_session_path(provider: "google")
      assert_select ".auth-providers form[action=?]", oauth_session_path(provider: "github")
      # Without data-turbo="false" the button silently does nothing: Turbo
      # follows the redirect with fetch and cannot leave the origin. The server
      # returns the same 302 either way, so this attribute is the only guard.
      assert_select ".auth-providers form[data-turbo='false']", count: 2
      assert_select "form[action=?]", session_path
    end
  end

  test "starting a sign-in redirects to the provider and remembers the state" do
    with_oauth do
      post oauth_session_path(provider: "google")

      assert_response :redirect
      location = URI(response.location)
      assert_equal "accounts.google.com", location.host
      query = Rack::Utils.parse_query(location.query)
      assert_equal "google-id", query["client_id"]
      assert_equal "code", query["response_type"]
      assert_equal oauth_callback_url(provider: "google"), query["redirect_uri"]
      assert query["state"].present?
    end
  end

  # These three stub a provider that would gladly hand back a verified address,
  # so the state check is the only thing left that can refuse. Without the stub
  # they passed even with state validation removed, because the token exchange
  # failed against the real endpoint and produced the same redirect.
  test "a callback with the wrong state signs nobody in" do
    with_oauth do
      post oauth_session_path(provider: "google")

      stub_provider("google", email: "attacker@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: "not-the-state" }
      end

      assert_redirected_to new_session_path
      assert_nil session[:user_id]
      assert_nil User.find_by(email_address: "attacker@example.com")
    end
  end

  test "a callback with no state at all signs nobody in" do
    with_oauth do
      stub_provider("google", email: "attacker@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc" }
      end

      assert_redirected_to new_session_path
      assert_nil session[:user_id]
      assert_nil User.find_by(email_address: "attacker@example.com")
    end
  end

  test "state is single use, so a replayed callback is refused" do
    with_oauth do
      state = start_and_capture_state("google")
      stub_provider("google", email: "new@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end
      assert_equal User.find_by(email_address: "new@example.com").id, session[:user_id]

      # The successful sign-in reset the session, so the state is gone with it.
      stub_provider("google", email: "someone.else@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_redirected_to new_session_path
      assert_nil User.find_by(email_address: "someone.else@example.com"), "a replayed state must not mint a second account"
    end
  end

  test "a state issued for one provider cannot be redeemed at another" do
    with_oauth do
      state = start_and_capture_state("google")

      stub_provider("github", email: "attacker@example.com") do
        get oauth_callback_path(provider: "github"), params: { code: "abc", state: state }
      end

      assert_redirected_to new_session_path
      assert_nil session[:user_id]
      assert_nil User.find_by(email_address: "attacker@example.com")
    end
  end

  test "an unverified address is refused rather than trusted" do
    with_oauth do
      state = start_and_capture_state("google")

      stub_provider("google", verified: false) do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_redirected_to new_session_path
      assert_nil session[:user_id]
      assert_nil User.find_by(email_address: "liar@example.com"), "no account may be created from an unverified address"
    end
  end

  test "a verified address signs in to the existing account rather than a second one" do
    existing = User.create!(email_address: "already@example.com")

    with_oauth do
      state = start_and_capture_state("google")
      stub_provider("google", email: "Already@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_equal existing.id, session[:user_id]
      assert_equal 1, User.where(email_address: "already@example.com").count
    end
  end

  test "the plus tag normalisation is the model's, so a tagged address is the same account" do
    existing = User.create!(email_address: "person@example.com")

    with_oauth do
      state = start_and_capture_state("google")
      stub_provider("google", email: "person+github@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_equal existing.id, session[:user_id], "User.normalizes strips the +tag, so this is one account"
    end
  end

  test "a send intent survives the round trip" do
    with_oauth do
      state = start_and_capture_state("google", intent: "send")
      stub_provider("google", email: "sender@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_redirected_to new_send_path
    end
  end

  test "an off-site return_to is dropped rather than followed" do
    with_oauth do
      state = start_and_capture_state("google", return_to: "https://evil.example.com/steal")
      stub_provider("google", email: "sender@example.com") do
        get oauth_callback_path(provider: "google"), params: { code: "abc", state: state }
      end

      assert_redirected_to files_path
    end
  end

  test "a provider that is not configured is not a route into anything" do
    post oauth_session_path(provider: "google")

    assert_redirected_to new_session_path
    assert_nil session[:user_id]
  end

  test "a cancelled sign-in says so and creates nothing" do
    with_oauth do
      state = start_and_capture_state("google")

      get oauth_callback_path(provider: "google"), params: { error: "access_denied", state: state }

      assert_redirected_to new_session_path
      assert_nil session[:user_id]
    end
  end

  private
    def with_oauth
      CREDENTIALS.each { |key, value| ENV[key] = value }
      yield
    ensure
      CREDENTIALS.each_key { |key| ENV.delete(key) }
    end

    def start_and_capture_state(provider, **params)
      post oauth_session_path(provider: provider, **params)
      Rack::Utils.parse_query(URI(response.location).query).fetch("state")
    end

    # Only the provider is replaced. Everything between the callback and the
    # session is the real code path, including the state check.
    class StubProvider
      attr_reader :key, :label

      def initialize(key, email:, verified:)
        @key = key
        @label = key.capitalize
        @email = email
        @verified = verified
      end

      def authorize_url(**) = "https://provider.test/authorize"

      def verified_email(**)
        raise OauthProvider::UnverifiedEmail unless @verified

        @email
      end
    end

    def stub_provider(key, email: nil, verified: true, &block)
      stubbing(OauthProvider, :find, StubProvider.new(key, email: email, verified: verified), &block)
    end
end
