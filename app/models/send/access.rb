# Issuing, checking and ending the recipient's link.
#
# Constants stay on Send because they are read from controllers, jobs and the
# managed distribution. A compact module definition puts only Send::Access in
# the lexical scope, so they are qualified here.
module Send::Access
  extend ActiveSupport::Concern

  def issue_access_token(at: Time.current)
    raw_token = SecureRandom.urlsafe_base64(32)
    self.access_token_digest = Digest::SHA256.hexdigest(raw_token)
    self.access_expires_at = at + Send::ACCESS_LIFETIME
    self.access_revoked_at = nil
    raw_token
  end

  def issue_access_token!
    transaction do
      raw_token = issue_access_token
      previous = access_expires_at_was
      save!
      AuditEvent.record!(
        action: "delivery.access_rotated",
        target: self,
        changed_fields: { "access_expires_at" => [ previous&.iso8601, access_expires_at&.iso8601 ] }
      )
      raw_token
    end
  end

  def access_token_valid?(raw_token)
    access_active? && ActiveSupport::SecurityUtils.secure_compare(access_token_digest, Digest::SHA256.hexdigest(raw_token.to_s))
  end

  def access_active?
    published? && !canceled? && access_token_digest.present? && access_revoked_at.nil? && access_expires_at&.future?
  end

  def revoke_access!
    transaction do
      update!(access_revoked_at: Time.current)
      AuditEvent.record!(action: "delivery.access_revoked", target: self)
    end
  end

  def access_state
    return "canceled" if canceled?
    return "revoked" if access_revoked_at?
    return "expired" if access_expires_at&.past?

    "active"
  end
end
