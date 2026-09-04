class SignInsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_private_cache

  def show
    @login_token = LoginToken.find_by(public_id: params[:public_id])
    redirect_to new_session_path, alert: "That sign-in link has expired. Ask for a new one." unless @login_token&.usable?
  end

  def create
    login_token = LoginToken.find_by(public_id: params[:public_id])
    user = LoginToken.consume(params[:public_id], params[:token])

    if user
      send_intent_started_at = session[:send_intent_started_at] || login_token&.created_at&.to_i
      reset_session
      session[:user_id] = user.id
      session[:authenticated_at] = Time.current.to_i
      if login_token&.intent == "send"
        session[:send_intent_started_at] = send_intent_started_at
        WideEvent.add(user_id: user.id, onboarding_event: "sign_in_completed", authentication_intent: "send")
      end
      redirect_to after_sign_in_path(intent: login_token&.intent, return_to: login_token&.return_to), notice: "Signed in."
    else
      redirect_to new_session_path, alert: "That sign-in link has expired. Ask for a new one."
    end
  end

  private
    def set_private_cache
      response.headers["Cache-Control"] = "private, no-store"
    end
end
