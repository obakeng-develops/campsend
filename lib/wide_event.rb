class WideEvent < ActiveSupport::CurrentAttributes
  attribute :payload, :payload_stack

  class << self
    def start(kind, **fields)
      self.payload_stack = [ *payload_stack, payload ] if payload
      self.payload = {
        event: kind,
        main: true,
        timestamp: Time.current.iso8601(3),
        service_name: "campsend",
        service_environment: Rails.env,
        service_version: ENV["KAMAL_VERSION"].presence || Campsend::VERSION,
        **fields
      }
    end

    def add(**fields)
      payload&.merge!(fields)
    end

    def add_error(error)
      add(error: true, exception_type: error.class.name)
    end

    def emit(**fields)
      return unless payload

      event = payload.merge(fields).compact
      Rails.logger.info JSON.generate(event)
      # The log line is the record. A sink is somewhere durable to put a copy,
      # and a broken one must never take a request down with it.
      Rails.configuration.x.wide_event_sink&.call(event)
    rescue StandardError
      nil
    ensure
      self.payload = payload_stack&.pop
    end
  end
end
