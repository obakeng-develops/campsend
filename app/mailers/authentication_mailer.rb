class AuthenticationMailer < ApplicationMailer
  def sign_in
    @login_token = params[:login_token]
    @user = @login_token.user
    @token = params[:token]
    @delivery = @login_token.delivery if @login_token.delivery&.email_status_held?
    subject = @delivery ? "Confirm your delivery to #{@delivery.recipient_email}" : "Your Campsend sign-in link"
    mail to: @user.email_address, subject: subject
  end
end
