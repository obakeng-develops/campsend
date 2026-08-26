class GetDeliveryTool < MCP::Tool
  tool_name "get_delivery"
  description "Get one delivery you sent, with its files and the times it was sent, first opened and first downloaded."
  annotations(read_only_hint: true, destructive_hint: false, idempotent_hint: true)
  input_schema(
    properties: {
      delivery_identifier: { type: "string", description: "The delivery's slug or public id, as returned by list_deliveries." }
    },
    required: [ "delivery_identifier" ]
  )

  class << self
    def call(delivery_identifier:, server_context:)
      user = server_context.fetch(:user)
      # Scoped to the caller first, so another user's delivery is not found
      # rather than forbidden.
      delivery = user.sends.with_attached_files.includes(:send_events)
                     .find_by(slug: delivery_identifier) ||
                 user.sends.with_attached_files.includes(:send_events)
                     .find_by(public_id: delivery_identifier)

      return McpTool.failure("No delivery with that identifier.") unless delivery

      McpTool.ok(DeliveryPresenter.detail(delivery))
    end
  end
end
