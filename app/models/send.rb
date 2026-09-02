class Send < ApplicationRecord
  ACCESS_LIFETIME = 30.days
  MAX_FILES = 20
  MAX_SEND_SIZE = 2.gigabytes
  RESERVED_SLUGS = %w[access api d download files opened rails session shared sign-in sends up].freeze
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  include Access, Events, Publication, Revisions, Slug

  # The ceiling for one delivery. MAX_SEND_SIZE is the ungated default; a
  # distribution that sells plans raises it through the policy. A nil user
  # resolves to the strictest limit, which is what an unsaved revision wants.
  def self.max_size_for(user)
    Campsend.policy.max_send_size_for(user)
  end

  def self.human_max_size_for(user)
    ActiveSupport::NumberHelper.number_to_human_size(max_size_for(user))
  end

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

  # Save this delivery and start it on its way: the policy admits it under a
  # user lock, the files are retained in the sender's library, and the mail job
  # is enqueued.
  #
  # Returns false and leaves errors on the record, the way save does. It lives
  # here because there are two callers, the composer and the MCP tool, and they
  # previously kept a copy each.
  def deliver!
    return false unless collection ? admit_from_collection : admit_and_save

    user.retain_files(files.blobs.to_a)
    DeliveryEmailJob.enqueue(self)
    true
  end

  private
    def admit_from_collection
      collection.with_lock do
        raise ActiveRecord::RecordNotFound if collection.removed_at?

        self.files = collection.blobs.to_a
        admit_and_save
      end
    end

    def admit_and_save
      user.with_lock do
        Campsend.policy.admit_delivery(user: user) { save }
      rescue Campsend::Policy::Denied => error
        WideEvent.add(outcome: error.outcome)
        # A denial is the highest-signal row in the table, and it is the one
        # nothing else in the product keeps.
        AuditEvent.record!(action: "delivery.created", outcome: "denied", denial_reason: error.outcome)
        errors.add(:base, error.message)
        false
      end
    end

    def collection_belongs_to_sender
      errors.add(:collection, "must belong to you") if collection && collection.user_id != user_id
    end
end
