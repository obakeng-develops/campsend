# What happened to a delivery, and the derived status the interface shows.
module Send::Events
  extend ActiveSupport::Concern

  AUDITED_EVENTS = {
    "sent" => "delivery.sent",
    "opened" => "delivery.opened",
    "downloaded" => "delivery.file_downloaded"
  }.freeze

  included do
    has_many :send_events, inverse_of: :delivery, dependent: :delete_all
    after_create :record_creation
  end

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

  def display_status
    return "canceled" if canceled?
    return "failed" if email_status_failed?
    return "scheduled" if scheduled?
    return "sending" if email_status_pending?
    return access_state unless access_state == "active"

    status || "sent"
  end

  private
    def record_creation
      AuditEvent.record!(action: scheduled? ? "delivery.scheduled" : "delivery.created", target: self)
    end
end
