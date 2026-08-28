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
  scope :for_actor, ->(actor) { where(actor_type: Current.actor_identity_for(actor).first, actor_id: actor.id) }
  scope :for_target, ->(record) { where(target_type: record.class.name, target_id: record.id) }

  class << self
    def record!(action:, target: nil, actor: :current, outcome: "succeeded", denial_reason: nil, changed_fields: nil, occurred_at: Time.current)
      actor_type, actor_id, actor_label = actor == :current ? Current.actor_identity : Current.actor_identity_for(actor)

      create!(
        action: action,
        outcome: outcome,
        denial_reason: denial_reason,
        actor_type: actor_type,
        actor_id: actor_id,
        actor_label: actor_label,
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
      def label_for(target)
        return if target.nil?
        return target.audit_label if target.respond_to?(:audit_label)

        target.try(:name) || target.try(:filename)&.to_s
      end
  end
end
