class ListDeliveriesTool < MCP::Tool
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  tool_name "list_deliveries"
  description "List the deliveries you have sent, newest first, with their status and when each was opened or downloaded."
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)
  input_schema(
    properties: {
      limit: { type: "integer", description: "How many to return. Defaults to #{DEFAULT_LIMIT}, at most #{MAX_LIMIT}." },
      status: { type: "string", description: "Only deliveries in this state: sent, opened, downloaded, scheduled, canceled, revoked or expired." }
    },
    required: []
  )

  class << self
    def call(server_context:, limit: DEFAULT_LIMIT, status: nil)
      user = server_context.fetch(:user)
      limit = limit.to_i.clamp(1, MAX_LIMIT)

      deliveries = user.sends.with_attached_files.includes(:send_events).order(created_at: :desc)
      # display_status is derived rather than stored, so filtering happens in Ruby.
      deliveries = deliveries.to_a
      deliveries = deliveries.select { |delivery| delivery.display_status == status } if status.present?

      McpTool.ok(deliveries: deliveries.first(limit).map { |delivery| DeliveryPresenter.summary(delivery) })
    end
  end
end
