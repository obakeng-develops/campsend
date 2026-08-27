class Send < ApplicationRecord
  ACCESS_LIFETIME = 30.days
  MAX_FILES = 20
  MAX_SEND_SIZE = 2.gigabytes
  RESERVED_SLUGS = %w[access api d download files opened rails session shared sign-in sends up].freeze
  SLUG_FORMAT = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  belongs_to :user
  belongs_to :collection, optional: true
  has_secure_token :public_id
  has_many :delivery_revisions, -> { order(number: :asc) }, inverse_of: :delivery, dependent: :destroy, autosave: true
  has_one :latest_revision, -> { order(number: :desc) }, class_name: "DeliveryRevision", inverse_of: :delivery
  has_many :send_events, inverse_of: :delivery, dependent: :delete_all
  enum :email_status, { pending: "pending", sent: "sent", failed: "failed" }, prefix: true, validate: true
  before_destroy :retain_published_slug
  after_create :record_creation

  scope :available, -> { where.not(published_at: nil).where(canceled_at: nil, access_revoked_at: nil, access_expires_at: Time.current..).where.not(access_token_digest: nil) }

  normalizes :recipient_email, with: ->(email) { email.strip.downcase.sub(/\+[^@]+/, "") }
  normalizes :slug, with: ->(slug) { slug.strip.downcase.presence }

  validates :recipient_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :message, length: { maximum: 500 }
  validates :slug, length: { maximum: 100 }, format: { with: SLUG_FORMAT }, exclusion: { in: RESERVED_SLUGS }, uniqueness: true, allow_nil: true
  validate :revision_is_valid
  validate :scheduled_at_is_future, if: :will_save_change_to_scheduled_at?
  validate :publication_state_is_consistent
  validate :collection_belongs_to_sender
  validate :published_slug_is_immutable, if: :will_save_change_to_slug?

  scope :with_attached_files, -> { includes(latest_revision: { files_attachments: :blob }) }

  def files
    files_revision.files
  end

  def files=(attachables)
    raise ActiveRecord::ReadOnlyRecord, "Published delivery files are immutable" if persisted?

    files.attach(attachables)
  end

  def replace_file!(attachment_id, replacement_blob)
    raise ActiveRecord::ReadOnlyRecord, "Collection deliveries follow their collection" if collection_id?

    with_lock do
      current = delivery_revisions.includes(files_attachments: :blob).order(number: :desc).first!
      replaced = current.files.attachments.find(attachment_id)
      blobs = current.files.attachments.map { |attachment| attachment == replaced ? replacement_blob : attachment.blob }
      append_revision!(blobs:).tap do
        AuditEvent.record!(
          action: "delivery.file_replaced",
          target: self,
          changed_fields: { "filename" => [ replaced.blob.filename.to_s, replacement_blob.filename.to_s ] }
        )
      end
    end
  end

  def revise_from_collection!(source)
    raise ActiveRecord::RecordNotFound unless collection_id == source.id && user_id == source.user_id

    with_lock do
      append_revision!(blobs: source.blobs.to_a, collection_name: source.name)
    end
  end

  def published?
    published_at.present?
  end

  def canceled?
    canceled_at.present?
  end

  def publication_pending?
    !published? && !canceled?
  end

  def scheduled?
    publication_pending? && scheduled_at.present?
  end

  def cancel!
    with_lock do
      return false unless publication_pending?

      update!(canceled_at: Time.current)
      AuditEvent.record!(action: "delivery.canceled", target: self)
    end
  end

  def update_before_publication(attributes)
    with_lock do
      return false unless publication_pending?

      update(attributes)
    end
  end

  def issue_access_token(at: Time.current)
    raw_token = SecureRandom.urlsafe_base64(32)
    self.access_token_digest = Digest::SHA256.hexdigest(raw_token)
    self.access_expires_at = at + ACCESS_LIFETIME
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

  def delivery_identifier
    slug.presence || public_id
  end

  def audit_label
    "#{delivery_identifier} to #{recipient_email}"
  end

  def self.find_by_delivery_identifier(identifier)
    find_by(slug: identifier) || find_by(public_id: identifier)
  end

  def self.find_by_delivery_identifier!(identifier)
    find_by_delivery_identifier(identifier) || raise(ActiveRecord::RecordNotFound)
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

  AUDITED_EVENTS = {
    "sent" => "delivery.sent",
    "opened" => "delivery.opened",
    "downloaded" => "delivery.file_downloaded"
  }.freeze

  def record_event!(event_type, occurred_at: Time.current)
    transaction do
      event = send_events.find_or_create_by!(event_type: event_type) { |item| item.occurred_at = occurred_at }
      update!(email_status: "sent", published_at: published_at || occurred_at) if event_type.to_s == "sent" && (!email_status_sent? || !published?)
      # Only on the first occurrence, because find_or_create_by returns the
      # existing row on a repeat and the log records what happened, not what
      # was asked for twice.
      if event.previously_new_record? && (action = AUDITED_EVENTS[event_type.to_s])
        AuditEvent.record!(action: action, target: self, occurred_at: occurred_at)
      end
      event
    end
  end

  def status
    %w[downloaded opened sent].find { |event_type| send_events.any? { |event| event.event_type == event_type } }
  end

  def access_state
    return "canceled" if canceled?
    return "revoked" if access_revoked_at?
    return "expired" if access_expires_at&.past?

    "active"
  end

  def display_status
    return "canceled" if canceled?
    return "failed" if email_status_failed?
    return "scheduled" if scheduled?
    return "sending" if email_status_pending?
    return access_state unless access_state == "active"

    status || "sent"
  end

  def recipient_name
    recipient_email.split("@").first.tr("._-", " ").titleize
  end

  private
    def record_creation
      AuditEvent.record!(action: scheduled? ? "delivery.scheduled" : "delivery.created", target: self)
    end

    def files_revision
      if new_record?
        @initial_revision ||= delivery_revisions.build(number: 1, collection_name: collection&.name)
        return @initial_revision
      end

      latest_revision
    end

    def append_revision!(blobs:, collection_name: nil)
      current = delivery_revisions.reorder(number: :desc).first!
      delivery_revisions.create!(number: current.number + 1, files: blobs, collection_name:).tap do
        association(:latest_revision).reset
      end
    end

    def revision_is_valid
      files_revision.errors.each { |error| errors.import(error) } unless files_revision.valid?
    end

    def scheduled_at_is_future
      errors.add(:scheduled_at, "must be in the future") if scheduled_at.present? && scheduled_at <= Time.current
    end

    def publication_state_is_consistent
      errors.add(:base, "A delivery cannot be published and canceled") if published? && canceled?
    end

    def collection_belongs_to_sender
      errors.add(:collection, "must belong to you") if collection && collection.user_id != user_id
    end

    def published_slug_is_immutable
      errors.add(:slug, "cannot change after publication") if published_at_in_database.present?
    end

    def retain_published_slug
      return unless published? && slug.present?

      errors.add(:base, "Published delivery links cannot be deleted")
      throw :abort
    end
end
