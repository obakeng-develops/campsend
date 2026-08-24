# A credential an agent can hold. Sessions are magic-link only, so there was
# nothing a program could authenticate with before this.
#
# Only the digest is stored, matching LoginToken and Send#access_token_digest.
# The raw token is shown once at creation and is unrecoverable afterwards.
class ApiToken < ApplicationRecord
  SCOPES = %w[read write].freeze
  # Distinctive enough for a secret scanner to recognize in a leaked file.
  PREFIX = "csnd_".freeze
  MAX_PER_USER = 10
  # A write on every request would be most of the cost of a read-only tool call.
  LAST_USED_RESOLUTION = 1.minute

  belongs_to :user

  normalizes :name, with: ->(name) { name.to_s.strip }

  validates :name, presence: true, length: { maximum: 60 }
  validates :scope, inclusion: { in: SCOPES }
  validate :name_is_unused, on: :create
  validate :expiry_is_future, if: :expires_at?

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.issue_for(user, name:, scope:, expires_at: nil)
    raw_token = "#{PREFIX}#{SecureRandom.urlsafe_base64(32)}"
    token = new(user: user, name: name, scope: scope, expires_at: expires_at, token_digest: digest(raw_token))
    [ token, (raw_token if token.save) ]
  end

  # Returns the token when the secret matches a live one, otherwise nil. Revoked
  # and expired tokens are indistinguishable from wrong ones on purpose.
  def self.authenticate(raw_token)
    return unless raw_token.to_s.start_with?(PREFIX)

    token = active.find_by(token_digest: digest(raw_token))
    token&.tap(&:record_use)
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def record_use
    return if last_used_at && last_used_at > LAST_USED_RESOLUTION.ago

    update_column(:last_used_at, Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  def revoked? = revoked_at.present?
  def expired? = expires_at&.past? || false
  def active? = !revoked? && !expired?
  def writable? = scope == "write"

  private
    def name_is_unused
      errors.add(:name, "is already in use") if user && user.api_tokens.active.exists?(name: name)
    end

    def expiry_is_future
      errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
    end
end
