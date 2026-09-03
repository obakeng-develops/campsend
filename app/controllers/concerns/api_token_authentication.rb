# Bearer-token authentication for machine callers, over the session-based
# Authentication that browsers use.
#
# A controller that only machines call requires a token. One that both reach,
# like direct uploads, accepts either: the token wins when it is present, and a
# browser falls through to its session.
module ApiTokenAuthentication
  extend ActiveSupport::Concern

  # Deliberately declares no callbacks. A machine-only controller opts out of
  # session authentication itself; a mixed one must not, or its browser callers
  # lose their guard.

  private
    def authenticate_api_token
      raw_token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
      return if raw_token.blank?

      @api_token = ApiToken.authenticate(raw_token)
      return render_api_error("Provide a valid Campsend API token.", :unauthorized) unless @api_token

      Current.actor = @api_token
      WideEvent.add(
        user_id: @api_token.user_id, api_token_id: @api_token.id, api_token_scope: @api_token.scope,
        **Campsend.policy.telemetry_for(@api_token.user)
      )
    end

    def require_api_token
      authenticate_api_token
      return if performed? || @api_token

      render_api_error("Provide a Campsend API token as a bearer token.", :unauthorized)
    end

    def require_writable_api_token
      return if @api_token.nil? || @api_token.writable?

      render_api_error("This token can only read. Create one that can read and send.", :forbidden)
    end

    # A machine cannot act on a redirect to the sign-in page, which is what
    # Authentication does by default.
    def require_authentication
      require_api_token
    end

    def current_user
      @api_token&.user || super
    end

    def render_api_error(message, status)
      WideEvent.add(outcome: "api_#{status}")
      render json: { error: message }, status: status
    end
end
