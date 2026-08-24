class CreateDeliveryTool < MCP::Tool
  tool_name "create_delivery"
  description "Send files you have already uploaded to one recipient. Campsend emails them a link that expires after 30 days."
  # Declared so a client knows this one changes state and can ask before calling it.
  annotations(read_only_hint: false, destructive_hint: false, idempotent_hint: false)
  input_schema(
    properties: {
      recipient_email: { type: "string", description: "The one person this delivery goes to." },
      file_ids: {
        type: "array",
        items: { type: "integer" },
        description: "Ids of files you already own, as returned by get_delivery. At most #{Send::MAX_FILES}."
      },
      message: { type: "string", description: "A note shown above the files, up to 500 characters." },
      slug: { type: "string", description: "Optional readable link, lowercase words separated by hyphens. Cannot be changed after sending." },
      scheduled_at: { type: "string", description: "Optional ISO 8601 time to send it instead of now. Must be in the future." }
    },
    required: [ "recipient_email", "file_ids" ]
  )

  class << self
    def call(recipient_email:, file_ids:, server_context:, message: nil, slug: nil, scheduled_at: nil)
      token = server_context.fetch(:api_token)
      return McpTool.failure("This token can only read. Create a token with the write scope to send deliveries.") unless token.writable?

      user = server_context.fetch(:user)
      blobs = owned_blobs(user, file_ids)
      return McpTool.failure("Some of those files are not yours, or do not exist.") unless blobs.size == Array(file_ids).uniq.size

      delivery = user.sends.new(recipient_email: recipient_email, message: message, slug: slug, scheduled_at: parse_time(scheduled_at), files: blobs)

      # The same path SendsController#create takes, rather than a second one that
      # could drift from it: the policy admits the save, then files are retained
      # and the email is enqueued.
      saved, denial = admit(user, delivery)
      return McpTool.failure(denial.message) if denial
      return McpTool.failure(delivery.errors.full_messages.to_sentence) unless saved

      user.retain_files(delivery.files.blobs.to_a)
      DeliveryEmailJob.enqueue(delivery)
      WideEvent.add(delivery_id: delivery.id, delivery_operation: delivery.scheduled? ? "scheduled" : "created", file_count: blobs.size)

      McpTool.ok(DeliveryPresenter.detail(delivery.reload))
    end

    private
      def owned_blobs(user, file_ids)
        ids = Array(file_ids).map { |id| Integer(id, exception: false) }.compact.uniq
        return [] if ids.empty?

        user.uploaded_blobs.where(id: ids).to_a
      end

      def admit(user, delivery)
        user.with_lock do
          [ Campsend.policy.admit_delivery(user: user) { delivery.save }, nil ]
        rescue Campsend::Policy::Denied => error
          WideEvent.add(outcome: error.outcome)
          [ false, error ]
        end
      end

      def parse_time(value)
        return if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        # Left nil so the model's own validation reports it rather than raising here.
        nil
      end
  end
end
