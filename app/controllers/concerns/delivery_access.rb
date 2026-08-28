module DeliveryAccess
  extend ActiveSupport::Concern

  included do
    before_action :set_private_cache
  end

  private
    def find_delivery
      Send.with_attached_files.find_by_delivery_identifier!(params[:public_id])
    end

    def require_delivery_access
      @send = find_delivery
      return head :not_found unless @send.access_active? && delivery_access_granted?(@send)

      # Whoever holds the link is acting as the recipient, and the address is
      # already on the delivery, so nothing new is learned by recording it.
      Current.actor = @send.recipient_email
    end

    def grant_delivery_access(delivery)
      session[:delivery_accesses] = (delivery_accesses + [ delivery_access_key(delivery) ]).uniq.last(10)
    end

    def delivery_accesses
      Array(session[:delivery_accesses])
    end

    def delivery_access_granted?(delivery)
      delivery_accesses.include?(delivery_access_key(delivery)) || authenticated? && current_user.email_address == delivery.recipient_email
    end

    def delivery_access_key(delivery)
      Digest::SHA256.hexdigest("#{delivery.public_id}:#{delivery.access_token_digest}")
    end

    def set_private_cache
      response.headers["Cache-Control"] = "private, no-store"
    end
end
