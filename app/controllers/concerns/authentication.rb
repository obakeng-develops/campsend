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

    def authenticated?
      current_user.present?
    end

    def require_authentication
      redirect_to new_session_path unless authenticated?
    end
end
