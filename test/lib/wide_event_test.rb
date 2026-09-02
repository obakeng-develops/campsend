require "test_helper"

class FailingWideEventJob < ApplicationJob
  def perform
    raise "job failed"
  end
end

class WideEventTest < ActionDispatch::IntegrationTest
  test "each request emits one structured event with request and user context" do
    user = User.create!(email_address: "sender@example.com")
    sign_in_as(user)

    events = capture_wide_events { get files_path }

    assert_equal 1, events.size
    event = events.first
    assert_equal "request", event["event"]
    assert_equal true, event["main"]
    assert_equal "campsend", event["service_name"]
    assert_equal "test", event["service_environment"]
    assert_equal Campsend::VERSION, event["service_version"]
    assert_equal "GET", event["method"]
    assert_equal "/files", event["path"]
    assert_equal 200, event["status"]
    assert_equal "success", event["outcome"]
    assert_equal user.id, event["user_id"]
    assert_not event.key?("user_plan")
    assert event["request_id"].present?
    assert event["duration_ms"].is_a?(Numeric)
  end

  test "health checks and assets are not logged" do
    events = capture_wide_events { get rails_health_check_path }

    assert_empty events
  end

  test "client errors have an explicit outcome" do
    user = User.create!(email_address: "sender@example.com")
    sign_in_as(user)

    events = capture_wide_events { post files_path, params: { files: [ "forged" ] } }

    assert_equal 1, events.size
    assert_equal 403, events.first["status"]
    assert_equal "client_error", events.first["outcome"]
  end

  test "a failure records the Accept header, and a success does not" do
    # A content-negotiation refusal is unreadable without the header that caused
    # it: Rails renders one as a 406 with nothing else in the row to explain it.
    refused = capture_wide_events { get new_session_path, headers: { "Accept" => "application/pdf" } }

    assert_equal 406, refused.first["status"]
    assert_equal "application/pdf", refused.first["request_accept"]

    # It says nothing on a request that worked, so it stays off those rows.
    served = capture_wide_events { get new_session_path, headers: { "Accept" => "text/html" } }

    assert_equal 200, served.first["status"]
    assert_nil served.first["request_accept"]
  end

  test "jobs emit one structured event with outcome" do
    user = User.create!(email_address: "sender@example.com")
    delivery = user.sends.new(recipient_email: "sam@example.com")
    delivery.files.attach(create_uploaded_blob(user))
    delivery.save!

    events = capture_wide_events { DeliveryEmailJob.perform_now(delivery) }

    assert_equal 1, events.size
    event = events.first
    assert_equal "job", event["event"]
    assert_equal "DeliveryEmailJob", event["job_class"]
    assert_equal "success", event["outcome"]
    assert_equal delivery.id, event["delivery_id"]
    assert_equal "publication", event["email_kind"]
    assert_equal "published", event["publication_outcome"]
    assert_equal delivery.reload.published_at.iso8601(3), event["published_at"]
    assert event["duration_ms"].is_a?(Numeric)
  end

  test "scheduling requests include operation context" do
    user = User.create!(email_address: "sender@example.com")
    sign_in_as(user)
    blob = create_uploaded_blob(user)
    scheduled_at = 2.days.from_now.change(usec: 0)

    events = capture_wide_events do
      post sends_path, params: {
        send: { recipient_email: "later@example.com", files: [ blob.signed_id ], scheduled_at: scheduled_at.iso8601 }
      }
    end

    event = events.first
    assert_equal "scheduled", event["delivery_operation"]
    assert_equal Send.last.id, event["delivery_id"]
    assert_equal scheduled_at.iso8601(3), event["scheduled_at"]
  end

  test "failed jobs record the error" do
    user = User.create!(email_address: "sender@example.com")
    drive_import = user.google_drive_imports.create!(google_file_id: "drive-file-123", filename: "Report.pdf")

    events = capture_wide_events do
      GoogleDriveImportJob.perform_now(drive_import, "forged-token")
    end

    event = events.first
    assert_equal "success", event["outcome"]
    assert_equal "failed", event["import_status"]
    assert_equal "failed", drive_import.reload.status
  end

  test "raised job errors are recorded and re-raised" do
    events = capture_wide_events do
      assert_raises(RuntimeError) { FailingWideEventJob.perform_now }
    end

    event = events.first
    assert_equal "error", event["outcome"]
    assert_equal true, event["error"]
    assert_equal "RuntimeError", event["exception_type"]
    assert_nil event["exception_message"]
  end

  test "a sink receives a copy of every event, and there is none by default" do
    assert_nil Rails.configuration.x.wide_event_sink

    shipped = []
    with_sink(->(event) { shipped << event }) do
      user = User.create!(email_address: "sender@example.com")
      sign_in_as(user)
      get files_path
    end

    assert_operator shipped.size, :>=, 1
    # Symbol keys, unlike the log line, which is JSON by the time anyone reads it.
    assert_equal :request, shipped.last[:event]
    assert_equal "/files", shipped.last[:path]
  end

  test "a sink that raises does not take the request with it" do
    with_sink(->(_event) { raise "the sink is down" }) do
      user = User.create!(email_address: "sender@example.com")
      sign_in_as(user)
      get files_path
    end

    assert_response :success
  end

  test "the log line is written even when the sink fails" do
    events = capture_wide_events do
      with_sink(->(_event) { raise "the sink is down" }) do
        user = User.create!(email_address: "sender@example.com")
        sign_in_as(user)
        get files_path
      end
    end

    assert_equal "/files", events.last["path"]
  end

  private
    def with_sink(sink)
      Rails.configuration.x.wide_event_sink = sink
      yield
    ensure
      Rails.configuration.x.wide_event_sink = nil
    end

    def capture_wide_events(&block)
      output = StringIO.new
      original_logger = Rails.logger
      Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(output))
      block.call
      output.rewind
      output.read.lines.filter_map do |line|
        JSON.parse(line.sub(/\A\[[^\]]*\] /, ""))
      rescue JSON::ParserError
        nil
      end
    ensure
      Rails.logger = original_logger
    end

    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end
end
