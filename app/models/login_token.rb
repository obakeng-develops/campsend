class LoginToken < ApplicationRecord
  LIFETIME = 15.minutes
  # A sign-in link is clicked seconds after it is asked for. A link that
  # confirms a held delivery is opened whenever its sender next reads mail.
  CONFIRMATION_LIFETIME = 7.days
  INTENTS = %w[send].freeze
  # A path on this site and nothing else. One leading slash, so a
  # protocol-relative //example.com cannot pass, and no backslash after it,
  # because some browsers read /\example.com as a host too. Whitespace is out
  # so a header cannot be split.
  RETURN_TO = %r{\A/(?![/\\])\S*\z}

  belongs_to :user
  belongs_to :delivery, class_name: "Send", foreign_key: :send_id, optional: true
  has_secure_token :public_id
  validates :intent, inclusion: { in: INTENTS }, allow_nil: true
  validates :return_to, format: { with: RETURN_TO }, length: { maximum: 200 }, allow_nil: true

  # return_to survives the email because it lives here rather than in the
  # session. The link is often opened on a different device from the one that
  # asked for it, and sign-in resets the session anyway.
  def self.issue_for(user, intent: nil, return_to: nil, delivery: nil)
    raw_token = SecureRandom.urlsafe_base64(32)
    token = create!(user: user, intent: intent, return_to: return_to.presence, delivery: delivery,
      token_digest: digest(raw_token), expires_at: (delivery ? CONFIRMATION_LIFETIME : LIFETIME).from_now)
    [ token, raw_token ]
  end

  def self.consume(public_id, raw_token)
    token = find_by(public_id: public_id, token_digest: digest(raw_token))
    return unless token

    token.with_lock do
      return if token.used_at? || token.expires_at.past?

      token.update!(used_at: Time.current)
      token.user
    end
  end

  def usable?
    !used_at? && expires_at.future?
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
  private_class_method :digest
end
