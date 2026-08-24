# Shapes deliveries for MCP callers.
#
# Access tokens, token digests and signed storage URLs are never included. A
# caller that wants a file downloads it through the browser, so nothing here
# hands out a way to reach bytes.
module DeliveryPresenter
  module_function

  def summary(delivery)
    {
      delivery_identifier: delivery.delivery_identifier,
      recipient_email: delivery.recipient_email,
      status: delivery.display_status,
      access_state: delivery.access_state,
      file_count: delivery.files.size,
      message: delivery.message,
      created_at: delivery.created_at.iso8601,
      published_at: delivery.published_at&.iso8601,
      scheduled_at: delivery.scheduled_at&.iso8601,
      access_expires_at: delivery.access_expires_at&.iso8601
    }
  end

  def detail(delivery)
    summary(delivery).merge(
      events: delivery.send_events.sort_by(&:occurred_at).map { |event|
        { type: event.event_type, occurred_at: event.occurred_at.iso8601 }
      },
      files: delivery.files.map { |file|
        { id: file.blob.id, filename: file.blob.filename.to_s, byte_size: file.blob.byte_size, content_type: file.blob.content_type }
      }
    )
  end
end
