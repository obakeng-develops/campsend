class ApiTokensController < ApplicationController
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { current_user.id }
  before_action :set_tokens

  def index
  end

  def create
    if @tokens.size >= ApiToken::MAX_PER_USER
      @token = ApiToken.new(token_params)
      @token.errors.add(:base, "You can have #{ApiToken::MAX_PER_USER} active tokens. Revoke one first.")
      return render :index, status: :unprocessable_entity
    end

    @token, @raw_token = ApiToken.issue_for(current_user, **token_params.to_h.symbolize_keys)

    if @raw_token
      WideEvent.add(api_token_id: @token.id, api_token_scope: @token.scope, token_operation: "created")
      set_tokens
      # Rendered once, straight into this response. A redirect would have to carry
      # the secret through the flash, which lives in the session cookie.
      render :index, status: :created
    else
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    token = current_user.api_tokens.find(params[:id])
    token.revoke!
    WideEvent.add(api_token_id: token.id, token_operation: "revoked")
    redirect_to api_tokens_path, notice: "Token revoked. Anything using it stops working now."
  end

  private
    def set_tokens
      @tokens = current_user.api_tokens.active.order(created_at: :desc).to_a
    end

    def token_params
      permitted = params.expect(api_token: [ :name, :scope, :expires_at ])
      permitted[:expires_at] = permitted[:expires_at].presence
      permitted
    end
end
