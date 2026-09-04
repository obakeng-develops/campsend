class AuthenticationEmailJob < ApplicationJob
  def perform(user, intent = nil, return_to = nil)
    WideEvent.add(user_id: user.id, email_kind: "authentication", authentication_intent: intent)
    login_token, raw_token = LoginToken.issue_for(user, intent: intent, return_to: return_to)
    AuthenticationMailer.with(login_token: login_token, token: raw_token).sign_in.deliver_now
  end
end
