class OauthSessionsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_private_cache
  before_action :load_provider
  # The callback is a GET the provider sends, so it carries no CSRF token and
  # state is what stands in for one. A limit here as well, because the email
  # path has two and this one inherits neither.
  rate_limit to: 10, within: 15.minutes, only: :callback, name: "oauth_ip"

  # POST, not a link. A GET here would let any page on the internet start a
  # sign-in, which is the hole omniauth-rails_csrf_protection exists to close.
  def create
    state = SecureRandom.urlsafe_base64(32)
    session[:oauth_state] = state
    session[:oauth_provider] = @provider.key
    session[:oauth_intent] = "send" if params[:intent] == "send"
    session[:oauth_return_to] = return_to

    start_send_intent if params[:intent] == "send"
    WideEvent.add(onboarding_event: "oauth_started", oauth_provider: @provider.key)

    redirect_to authorize_url(state), allow_other_host: true
  end

  def callback
    return refuse("Sign-in was cancelled.") if params[:error].present?
    return refuse unless valid_state?

    email_address = @provider.verified_email(code: params[:code].to_s, redirect_uri: callback_url)
    return refuse("#{@provider.label} did not confirm that email address. Use a sign-in link instead.") if email_address.blank?

    sign_in User.find_or_create_by!(email_address: email_address)
  rescue OauthProvider::UnverifiedEmail
    refuse("Your #{@provider.label} email address is not verified. Verify it there, or use a sign-in link instead.")
  rescue ActiveRecord::RecordInvalid
    refuse("#{@provider.label} returned an address we cannot use. Use a sign-in link instead.")
  end

  private
    # The provider comes from a frozen list, so this can only ever be one of two
    # hosts. Checked anyway: it is the one redirect in the app that leaves the
    # site, and an allowlist is cheaper than the bug.
    def authorize_url(state)
      url = @provider.authorize_url(redirect_uri: callback_url, state: state)
      raise ArgumentError, "refusing to redirect off the allowlist" unless
        OauthProvider::AUTHORIZE_HOSTS.include?(URI(url).host)

      url
    end

    def load_provider
      @provider = OauthProvider.find(params[:provider])
      redirect_to new_session_path, alert: "That sign-in method is not available." unless @provider
    end

    # Single use, and compared in constant time. Whichever way this fails the
    # answer is the same, so a caller learns nothing from which check tripped.
    def valid_state?
      expected = session.delete(:oauth_state)
      provider = session.delete(:oauth_provider)

      expected.present? &&
        params[:state].present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, params[:state].to_s) &&
        provider == @provider.key
    end

    def sign_in(user)
      intent = session[:oauth_intent]
      destination = session[:oauth_return_to]
      send_intent_started_at = session[:send_intent_started_at]

      reset_session
      session[:user_id] = user.id
      session[:authenticated_at] = Time.current.to_i
      if intent == "send"
        session[:send_intent_started_at] = send_intent_started_at
        WideEvent.add(user_id: user.id, onboarding_event: "sign_in_completed", authentication_intent: "send")
      end
      WideEvent.add(user_id: user.id, oauth_provider: @provider.key)

      redirect_to after_sign_in_path(intent: intent, return_to: destination), notice: "Signed in."
    end

    def refuse(message = "That sign-in could not be completed. Try again.")
      WideEvent.add(onboarding_event: "oauth_refused", oauth_provider: @provider&.key)
      redirect_to new_session_path, alert: message
    end

    def callback_url
      oauth_callback_url(provider: @provider.key)
    end

    # Same rule as the email path: a path on this site or nothing.
    def return_to
      candidate = params[:return_to].to_s
      candidate if candidate.match?(LoginToken::RETURN_TO) && candidate.length <= 200
    end

    def set_private_cache
      response.headers["Cache-Control"] = "private, no-store"
    end
end
