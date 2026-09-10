require "net/http"
require "uri"

# An OAuth sign-in provider, configured entirely from the environment.
#
# No gem. The authorization-code flow is two HTTP calls and a comparison, and
# the security of it lives in the `state` check and in refusing an unverified
# address — neither of which a dependency would decide for us. Same reasoning as
# bin/search-console: a signed request is not worth a supply chain.
#
# A provider with no credentials in the environment does not exist. Nobody
# self-hosting Campsend should have to register an OAuth client to sign in.
class OauthProvider
  # A provider hands back an address it says it has verified. Anything less is
  # an invitation to sign in as somebody else, so an unverified address is
  # treated as no address at all.
  class UnverifiedEmail < StandardError; end

  DEFINITIONS = {
    "google" => {
      label: "Google",
      authorize_url: "https://accounts.google.com/o/oauth2/v2/auth",
      token_url: "https://oauth2.googleapis.com/token",
      scope: "openid email",
      env_prefix: "GOOGLE_OAUTH"
    },
    "github" => {
      label: "GitHub",
      authorize_url: "https://github.com/login/oauth/authorize",
      token_url: "https://github.com/login/oauth/access_token",
      scope: "user:email",
      env_prefix: "GITHUB_OAUTH"
    }
  }.freeze

  # Every host this class will ever send somebody to, taken from the definitions
  # above rather than written twice. The controller checks a URL against this
  # before redirecting, so a future change to authorize_url cannot turn the
  # sign-in button into an open redirect.
  AUTHORIZE_HOSTS = DEFINITIONS.values.map { |d| URI(d[:authorize_url]).host }.freeze

  attr_reader :key, :label

  def self.all
    DEFINITIONS.keys.map { |key| new(key) }
  end

  def self.configured
    all.select(&:configured?)
  end

  def self.find(key)
    provider = new(key) if DEFINITIONS.key?(key.to_s)
    provider if provider&.configured?
  end

  def initialize(key)
    @key = key.to_s
    definition = DEFINITIONS.fetch(@key)
    @label = definition[:label]
    @definition = definition
  end

  def configured?
    client_id.present? && client_secret.present?
  end

  def authorize_url(redirect_uri:, state:)
    query = {
      client_id: client_id,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: @definition[:scope],
      state: state
    }
    # Google will reuse a previous grant without asking again, which is the
    # point of signing in with Google.
    "#{@definition[:authorize_url]}?#{query.to_query}"
  end

  # The verified address behind an authorization code, or nil if the provider
  # will not vouch for one.
  def verified_email(code:, redirect_uri:)
    token = access_token(code: code, redirect_uri: redirect_uri)
    return if token.blank?

    @key == "github" ? github_email(token) : google_email(token)
  end

  private
    def client_id = ENV["#{@definition[:env_prefix]}_CLIENT_ID"]
    def client_secret = ENV["#{@definition[:env_prefix]}_CLIENT_SECRET"]

    def access_token(code:, redirect_uri:)
      response = post_json(@definition[:token_url],
        client_id: client_id,
        client_secret: client_secret,
        code: code,
        grant_type: "authorization_code",
        redirect_uri: redirect_uri)

      response["access_token"]
    end

    # Google states verification on the userinfo response itself.
    def google_email(token)
      profile = get_json("https://openidconnect.googleapis.com/v1/userinfo", token)
      raise UnverifiedEmail unless profile["email_verified"]

      profile["email"].presence || raise(UnverifiedEmail)
    end

    # GitHub's /user carries whatever address somebody chose to display, which
    # may be unverified or absent. /user/emails is the only place that says
    # which one is both primary and verified.
    def github_email(token)
      addresses = get_json("https://api.github.com/user/emails", token)
      primary = Array(addresses).find { |address| address["primary"] && address["verified"] }
      raise UnverifiedEmail unless primary

      primary["email"]
    end

    def post_json(url, **params)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri, "Accept" => "application/json")
      request.set_form_data(params)
      parse(perform(uri, request))
    end

    def get_json(url, token)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri,
        "Accept" => "application/json",
        "Authorization" => "Bearer #{token}",
        "User-Agent" => "Campsend")
      parse(perform(uri, request))
    end

    def perform(uri, request)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end
    end

    def parse(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end
end
