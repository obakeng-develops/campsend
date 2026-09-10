require "test_helper"

class OauthProviderTest < ActiveSupport::TestCase
  test "a provider without both halves of its credentials does not exist" do
    assert_empty OauthProvider.configured

    with_env("GOOGLE_OAUTH_CLIENT_ID" => "id") do
      assert_empty OauthProvider.configured, "an id without a secret is not configured"
      assert_nil OauthProvider.find("google")
    end

    with_env("GOOGLE_OAUTH_CLIENT_ID" => "id", "GOOGLE_OAUTH_CLIENT_SECRET" => "secret") do
      assert_equal [ "google" ], OauthProvider.configured.map(&:key)
      assert OauthProvider.find("google")
    end
  end

  test "an unknown provider is never found" do
    assert_nil OauthProvider.find("myspace")
    assert_nil OauthProvider.find("")
  end

  test "the authorize url asks for a code and carries the state" do
    with_env("GITHUB_OAUTH_CLIENT_ID" => "gh-id", "GITHUB_OAUTH_CLIENT_SECRET" => "gh-secret") do
      url = OauthProvider.find("github").authorize_url(redirect_uri: "https://campsend.app/auth/github/callback", state: "st4te")
      query = Rack::Utils.parse_query(URI(url).query)

      assert_equal "https://github.com/login/oauth/authorize", url.split("?").first
      assert_equal "gh-id", query["client_id"]
      assert_equal "code", query["response_type"]
      assert_equal "st4te", query["state"]
      assert_equal "user:email", query["scope"]
    end
  end

  test "google is believed only when it says the address is verified" do
    with_google do |provider|
      assert_equal "yes@example.com", email_from(provider, { "email" => "yes@example.com", "email_verified" => true })

      assert_raises OauthProvider::UnverifiedEmail do
        email_from(provider, { "email" => "no@example.com", "email_verified" => false })
      end

      assert_raises OauthProvider::UnverifiedEmail do
        email_from(provider, { "email_verified" => true })
      end
    end
  end

  test "github's displayed address is ignored in favour of the primary verified one" do
    with_github do |provider|
      addresses = [
        { "email" => "display@example.com", "primary" => false, "verified" => true },
        { "email" => "unverified@example.com", "primary" => true, "verified" => false },
        { "email" => "real@example.com", "primary" => true, "verified" => true }
      ]

      assert_equal "real@example.com", email_from(provider, addresses)
    end
  end

  test "github with nothing both primary and verified yields no address" do
    with_github do |provider|
      assert_raises OauthProvider::UnverifiedEmail do
        email_from(provider, [ { "email" => "a@example.com", "primary" => true, "verified" => false } ])
      end

      assert_raises OauthProvider::UnverifiedEmail do
        email_from(provider, [])
      end
    end
  end

  test "a token exchange that yields nothing yields no address" do
    with_google do |provider|
      stubbing(provider, :access_token, nil) do
        assert_nil provider.verified_email(code: "abc", redirect_uri: "https://campsend.app/cb")
      end
    end
  end

  private
    def with_env(values)
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      values.each_key { |key| ENV.delete(key) }
    end

    def with_google(&block)
      with_env("GOOGLE_OAUTH_CLIENT_ID" => "id", "GOOGLE_OAUTH_CLIENT_SECRET" => "secret") do
        block.call(OauthProvider.find("google"))
      end
    end

    def with_github(&block)
      with_env("GITHUB_OAUTH_CLIENT_ID" => "id", "GITHUB_OAUTH_CLIENT_SECRET" => "secret") do
        block.call(OauthProvider.find("github"))
      end
    end

    # Stubs only the two HTTP calls, so the verification logic under test is real.
    def email_from(provider, payload)
      stubbing(provider, :access_token, "token") do
        stubbing(provider, :get_json, payload) do
          provider.verified_email(code: "abc", redirect_uri: "https://campsend.app/cb")
        end
      end
    end
end
