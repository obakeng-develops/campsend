module Campsend
  class Policy
    class Denied < StandardError
      attr_reader :outcome

      def initialize(message, outcome:)
        @outcome = outcome
        super(message)
      end
    end

    def admit_storage(user:, byte_size:)
      yield
    end

    def admit_delivery(user:)
      yield
    end

    # How much one delivery may hold. Ungated here, so a self-hosted install
    # keeps whatever Send::MAX_SEND_SIZE says. A distribution that sells plans
    # overrides it per plan.
    #
    # Above roughly 5 GB the browser cannot upload at all: R2 and S3 cap a
    # single presigned PUT there, and Active Storage's direct upload issues
    # exactly one. Raising this past that needs multipart upload first.
    def max_send_size_for(user)
      Send::MAX_SEND_SIZE
    end

    def storage_service_name_for(user:)
    end

    def storage_key_prefix_for(user:)
      "users/#{user.id}/blobs"
    end

    def usage_for(user)
    end

    # Storage a distribution meters for this user as { used:, limit: }, or nil
    # when storage is not metered. The composer states it beside the
    # per-delivery limit, because a delivery can be refused for either reason
    # and only one of the two is obvious from the file you picked.
    def storage_usage_for(user)
    end

    def telemetry_for(user)
      {}
    end
  end

  class << self
    attr_accessor :policy
  end

  self.policy = Policy.new
end
