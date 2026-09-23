ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    def create_uploaded_blob(user, content: "hello", filename: "hello.txt", content_type: "text/plain")
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      ).tap { |blob| blob.update!(uploader_id: user.id) }
    end

    def blob_params(content: "hello", filename: "hello.txt")
      {
        filename: filename,
        byte_size: content.bytesize,
        checksum: Base64.strict_encode64(::Digest::MD5.digest(content)),
        content_type: "text/plain"
      }
    end
  end
end

module ActionDispatch
  class IntegrationTest
    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end

    # The landing and sign-in forms with the send intent: a new address lands
    # in the composer as a guest, without an email.
    def start_guest_as(email_address)
      post session_path, params: { email_address: email_address, intent: "send" }
    end
  end
end
