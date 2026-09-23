class SignInsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_private_cache

  def show
    @login_token = LoginToken.find_by(public_id: params[:public_id])
    return redirect_to new_session_path, alert: "That sign-in link has expired. Ask for a new one." unless @login_token&.usable?

    @delivery = held_delivery(@login_token)
  end

  def create
    login_token = LoginToken.find_by(public_id: params[:public_id])
    user = LoginToken.consume(params[:public_id], params[:token])

    if user
      send_intent_started_at = session[:send_intent_started_at] || login_token&.created_at&.to_i
      start_session_for(user)
      user.verify!
      delivery = held_delivery(login_token)
      if delivery&.confirm!
        WideEvent.add(user_id: user.id, delivery_id: delivery.id, delivery_operation: "confirmed", onboarding_event: "delivery_confirmed")
      elsif login_token&.intent == "send"
        WideEvent.add(user_id: user.id, onboarding_event: "sign_in_completed", authentication_intent: "send")
      end
      session[:send_intent_started_at] = send_intent_started_at if login_token&.intent == "send"
      return_to = login_token&.return_to.presence || (send_path(delivery) if delivery)
      notice = delivery ? "We’re emailing the delivery link to #{delivery.recipient_email}." : "Signed in."
      redirect_to after_sign_in_path(intent: login_token&.intent, return_to: return_to), notice: notice
    else
      redirect_to new_session_path, alert: "That sign-in link has expired. Ask for a new one."
    end
  end

  private
    def set_private_cache
      response.headers["Cache-Control"] = "private, no-store"
    end

    # The delivery a link confirms, if it is still waiting. Scoped through the
    # token's own user, so a link can never confirm someone else's delivery.
    def held_delivery(login_token)
      return unless login_token&.send_id

      login_token.user.sends.email_status_held.find_by(id: login_token.send_id)
    end
end
