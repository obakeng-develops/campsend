# What people and machines did, kept for the customer rather than for an
# incident. Wide events answer "what happened in the last few days of retained
# logs" for the operator. This answers "who revoked that delivery, and when",
# months later, after the records involved may be gone.
#
# The two are joined by request_id and are deliberately not the same thing.
# Wide events strip email addresses; an audit row without the recipient is
# useless to the person reading it.
class AuditEvent < ApplicationRecord
  class Immutable < StandardError; end

  RETENTION = 1.year
  OUTCOMES = %w[succeeded denied].freeze
  ACTOR_TYPES = %w[user api_token recipient system].freeze

  validates :action, presence: true
  validates :outcome, inclusion: { in: OUTCOMES }
  validates :actor_type, inclusion: { in: ACTOR_TYPES }

  # Append-only in practice, enforced here rather than by convention. The
  # retention sweep uses delete_all, which skips callbacks on purpose.
  before_update { raise Immutable, "Audit events cannot be changed" }
  before_destroy { raise Immutable, "Audit events cannot be deleted" }

  scope :newest_first, -> { order(occurred_at: :desc, id: :desc) }
  scope :for_account, ->(user) { where(user_id: user.id) }
  scope :for_target, ->(record) { where(target_type: record.class.name, target_id: record.id) }
  scope :with_action, ->(action) { where(action: action) if action.present? }
  scope :since, ->(date) { where(occurred_at: date.beginning_of_day..) if date.present? }
  scope :until_end_of, ->(date) { where(occurred_at: ..date.end_of_day) if date.present? }

  # Sentences rather than dotted identifiers, because the reader is a customer
  # and the log is only useful if it reads like one.
  DESCRIPTIONS = {
    "delivery.created" => "Created a delivery",
    "delivery.scheduled" => "Scheduled a delivery",
    "delivery.canceled" => "Canceled a delivery",
    "delivery.sent" => "Delivery link emailed",
    "delivery.opened" => "Opened the delivery",
    "delivery.file_downloaded" => "Downloaded a file",
    "delivery.access_revoked" => "Revoked recipient access",
    "delivery.access_rotation_requested" => "Asked for a new delivery link",
    "delivery.access_rotated" => "New delivery link issued",
    "delivery.file_replaced" => "Replaced a file",
    "file.removed" => "Removed a file from My Files",
    "file.uploaded" => "Uploaded a file",
    "api_token.created" => "Created an API token",
    "api_token.revoked" => "Revoked an API token"
  }.freeze

  def description = DESCRIPTIONS.fetch(action, action.tr("._", " ").capitalize)

  def denied? = outcome == "denied"

  def actor_description
    case actor_type
    when "user" then actor_label
    when "api_token" then "#{actor_label} (API token)"
    when "recipient" then "#{actor_label} (recipient)"
    else "Campsend"
    end
  end

  class << self
    def record!(action:, target: nil, actor: :current, outcome: "succeeded", denial_reason: nil, changed_fields: nil, occurred_at: Time.current)
      resolved = actor == :current ? Current.actor : actor
      actor_type, actor_id, actor_label = Current.actor_identity_for(resolved)

      create!(
        action: action,
        outcome: outcome,
        denial_reason: denial_reason,
        actor_type: actor_type,
        actor_id: actor_id,
        actor_label: actor_label,
        user_id: account_for(target, resolved),
        target_type: target&.class&.name,
        target_id: target&.id,
        target_label: label_for(target),
        changed_fields: changed_fields.presence,
        # Joins this row to the wide event for the same request.
        request_id: WideEvent.payload&.dig(:request_id),
        occurred_at: occurred_at,
        recorded_at: Time.current
      )
    end

    def purge_expired!(now: Time.current)
      where(occurred_at: ...(now - RETENTION)).delete_all
    end

    private
      # A recipient opening a delivery is the sender's event to read, so the
      # target's owner wins over the actor.
      def account_for(target, actor)
        return target.user_id if target.respond_to?(:user_id)

        case actor
        when User then actor.id
        when ApiToken then actor.user_id
        end
      end

      def label_for(target)
        return if target.nil?
        return target.audit_label if target.respond_to?(:audit_label)

        target.try(:name) || target.try(:filename)&.to_s
      end
  end
end
