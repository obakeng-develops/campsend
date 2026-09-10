ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Minitest 6 dropped minitest/mock, so there is no Object#stub any more.
    # This is the whole of what we used it for: swap one method for a fixed
    # answer, put the original back afterwards, and add no dependency to do it.
    def stubbing(object, method, value)
      original = object.method(method)
      object.define_singleton_method(method) { |*, **| value }
      yield
    ensure
      object.singleton_class.send(:remove_method, method)
      object.define_singleton_method(method, original) if original.owner == object.singleton_class
    end

    def create_uploaded_blob(user, content: "hello", filename: "hello.txt", content_type: "text/plain")
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(content),
        filename: filename,
        content_type: content_type
      ).tap { |blob| blob.update!(uploader_id: user.id) }
    end
  end
end
