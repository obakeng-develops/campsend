module Authentication
  extend ActiveSupport::Concern
  SESSION_LIFETIME = 30.days

  included do
    before_action :require_authentication
    before_action :require_verified_user
    helper_method :current_user, :authenticated?, :verified?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
      skip_before_action :require_verified_user, **options
    end

    # A guest has typed an address and proven nothing. They may build and
    # hold a delivery; everything else waits for the confirmation link.
    def allow_unverified_access(**options)
      skip_before_action :require_verified_user, **options
    end
  end

  private
    def current_user
      return if session[:authenticated_at].to_i < SESSION_LIFETIME.ago.to_i
      return @current_user if defined?(@current_user)

      user = User.find_by(id: session[:user_id])
      # A guest session authenticates an unverified address only. The moment
      # the address is confirmed anywhere, whoever merely typed it is a
      # stranger again.
      user = nil if user && session[:guest] && user.verified?
      if user
        Current.actor = user
        WideEvent.add(user_id: user.id, **Campsend.policy.telemetry_for(user))
      end
      @current_user = user
    end

  # Where somebody lands once they are signed in. One definition, because the
  # sign-in form and the emailed link both have to answer it and there is no
  # reason for them to disagree. return_to wins when there is one: it is the
  # more specific answer, and it is the only one that can point at a page core
  # does not know about.
  def after_sign_in_path(intent: nil, return_to: nil)
    return return_to if return_to.present?

    intent.to_s == "send" ? new_send_path : files_path
  end

  def authenticated?
      current_user.present?
    end

    def verified?
      current_user&.verified? || false
    end

    def require_authentication
      redirect_to new_session_path unless authenticated?
    end

    def require_verified_user
      redirect_to new_session_path, alert: "Confirm your email address to continue." unless verified?
    end

    # A guest keeps their session rather than getting a fresh one: the composer
    # they are standing in was rendered with its token, and the next thing it
    # does is submit.
    def start_session_for(user, guest: false)
      reset_session unless guest
      session[:user_id] = user.id
      session[:authenticated_at] = Time.current.to_i
      session[:guest] = true if guest
      @current_user = user
    end
end
