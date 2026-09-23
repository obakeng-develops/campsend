class DeliveryEmailJob < ApplicationJob
  DELIVERY_ERRORS = [ Net::SMTPServerBusy, Net::SMTPUnknownError, Net::OpenTimeout, Net::ReadTimeout, SocketError ].freeze
  discard_on ActiveJob::DeserializationError

  retry_on(*DELIVERY_ERRORS, wait: 10.seconds, attempts: 3) do |job, _error|
    delivery = job.arguments.first.reload
    delivery.update!(email_status: "failed") if delivery.publication_pending?
  end


  def self.enqueue(delivery)
    wake_at = delivery.scheduled_at&.future? ? delivery.scheduled_at : Time.current
    job = wake_at.future? ? set(wait_until: wake_at).perform_later(delivery) : perform_later(delivery)
    delivery.update_column(:publication_enqueued_at, wake_at)
    job
  end

  def perform(delivery)
    WideEvent.add(user_id: delivery.user_id, delivery_id: delivery.id, email_kind: "publication", scheduled_at: delivery.scheduled_at&.iso8601(3))
    delivery.with_lock do
      if delivery.canceled?
        WideEvent.add(publication_outcome: "canceled")
        next
      end
      if delivery.email_status_held?
        WideEvent.add(publication_outcome: "held")
        next
      end
      if delivery.published?
        WideEvent.add(publication_outcome: "already_published", published_at: delivery.published_at.iso8601(3))
        next
      end
      if delivery.scheduled_at&.future?
        self.class.enqueue(delivery)
        WideEvent.add(publication_outcome: "rescheduled", scheduled_at: delivery.scheduled_at.iso8601(3))
        next
      end

      raw_token = delivery.issue_access_token
      DeliveryMailer.with(send: delivery, access_token: raw_token).files_ready.deliver_now
      published_at = Time.current
      delivery.access_expires_at = published_at + Send::ACCESS_LIFETIME
      delivery.update!(published_at: published_at, email_status: "sent")
      delivery.record_event!(:sent, occurred_at: published_at)
      WideEvent.add(publication_outcome: "published", published_at: published_at.iso8601(3))
    end
  rescue *DELIVERY_ERRORS
    raise
  rescue StandardError
    delivery.reload.update!(email_status: "failed") if delivery.publication_pending?
    raise
  end
end
