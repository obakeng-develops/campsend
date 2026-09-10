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
end
