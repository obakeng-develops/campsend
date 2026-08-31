class Send < ApplicationRecord
  ACCESS_LIFETIME = 30.days
  MAX_FILES = 20
  MAX_SEND_SIZE = 2.gigabytes
  RESERVED_SLUGS = %w[access api d download files opened rails session shared sign-in sends up].freeze
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  include Access, Events, Publication, Revisions, Slug

  belongs_to :user
  belongs_to :collection, optional: true
  has_secure_token :public_id
  enum :email_status, { pending: "pending", sent: "sent", failed: "failed" }, prefix: true, validate: true

  scope :available, -> { where.not(published_at: nil).where(canceled_at: nil, access_revoked_at: nil, access_expires_at: Time.current..).where.not(access_token_digest: nil) }

  normalizes :recipient_email, with: ->(email) { email.strip.downcase.sub(/\+[^@]+/, "") }

  validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, length: { maximum: 500 }
  validate :collection_belongs_to_sender

  def recipient_name
    recipient_email.split("@").first.tr("._-", " ").titleize
  end

  private
    def collection_belongs_to_sender
      errors.add(:collection, "must belong to you") if collection && collection.user_id != user_id
    end
end
