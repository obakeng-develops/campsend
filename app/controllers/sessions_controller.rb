class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 5, within: 15.minutes, only: :create, name: "ip"
  rate_limit to: 5, within: 15.minutes, only: :create, name: "email", by: -> { params[:email_address].to_s.strip.downcase }

  def new
    redirect_to(after_sign_in_path(intent: params[:intent], return_to: return_to)) if authenticated?
    session.delete(:sign_in_email) if params[:change_email]
    @sign_in_email = session[:sign_in_email]
    @sign_in_intent = @sign_in_email ? session[:sign_in_intent] : ("send" if params[:intent] == "send")
    start_send_intent if @sign_in_intent == "send"
  end

  def create
    email_address = params.expect(:email_address).to_s.strip.downcase
    intent = params[:intent] == "send" ? "send" : nil
    start_send_intent if intent
    user = User.find_or_create_by!(email_address: email_address)
    WideEvent.add(onboarding_event: "sign_in_requested", authentication_intent: intent) if intent
    AuthenticationEmailJob.perform_later(user, intent, return_to)

    session[:sign_in_email] = email_address
    session[:sign_in_intent] = intent
    redirect_to new_session_path(intent: intent, return_to: return_to)
  rescue ActiveRecord::RecordInvalid
    flash.now[:alert] = "Enter a valid email address."
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def destroy
    reset_session
    redirect_to root_path
  end

  private
    # Somewhere on this site to land after signing in, so a visitor who was part
    # way through something arrives back at it rather than at their files. An
    # extension can send someone here from a page core knows nothing about and
    # still get them home. Anything that is not a path on this site is dropped
    # rather than corrected, because there is no honest way to guess what was
    # meant.
    def return_to
      candidate = params[:return_to].to_s
      candidate if candidate.match?(LoginToken::RETURN_TO) && candidate.length <= 200
    end

    def start_send_intent
      return if session[:send_intent_started_at]

      session[:send_intent_started_at] = Time.current.to_i
      WideEvent.add(onboarding_event: "send_intent_started")
    end
end
