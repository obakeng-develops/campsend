module Authentication
  extend ActiveSupport::Concern
  SESSION_LIFETIME = 30.days

  included do
    before_action :require_authentication
    helper_method :current_user, :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def current_user
      return if session[:authenticated_at].to_i < SESSION_LIFETIME.ago.to_i

      @current_user ||= User.find_by(id: session[:user_id]).tap do |user|
        next unless user

        Current.actor = user
        WideEvent.add(user_id: user.id, **Campsend.policy.telemetry_for(user))
      end
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

    def require_authentication
      redirect_to new_session_path unless authenticated?
    end
end
