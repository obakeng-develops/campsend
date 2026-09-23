require "test_helper"

class DeliveryEmailJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    user = User.create!(email_address: "sender@example.com")
    @delivery = user.sends.new(recipient_email: "sam@example.com")
    @delivery.files.attach(create_uploaded_blob(user))
    @delivery.save!
  end

  test "records sent only after email delivery succeeds" do
    DeliveryEmailJob.perform_now(@delivery)

    assert_equal "sent", @delivery.reload.status
    assert @delivery.published?
    assert @delivery.email_status_sent?
    assert @delivery.access_active?
    assert_equal @delivery.published_at, @delivery.send_events.sent.pick(:occurred_at)
  end

  test "reschedules when the database schedule is still in the future" do
    @delivery.update!(scheduled_at: 2.hours.from_now)

    assert_enqueued_with(job: DeliveryEmailJob, at: @delivery.scheduled_at) do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        DeliveryEmailJob.perform_now(@delivery)
      end
    end

    assert_nil @delivery.reload.published_at
  end

  test "duplicate publication jobs send one email" do
    assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
      DeliveryEmailJob.perform_now(@delivery)
      DeliveryEmailJob.perform_now(@delivery)
    end

    assert @delivery.reload.published?
  end

  test "a held delivery is never published, whoever enqueues it" do
    @delivery.update!(email_status: "held")

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      DeliveryEmailJob.perform_now(@delivery)
    end

    assert_nil @delivery.reload.published_at
    assert @delivery.email_status_held?
  end

  test "canceled deliveries do not publish" do
    @delivery.update!(scheduled_at: 2.hours.from_now)
    @delivery.cancel!

    assert_no_difference -> { ActionMailer::Base.deliveries.size } do
      DeliveryEmailJob.perform_now(@delivery)
    end

    assert_nil @delivery.reload.published_at
  end

  test "publication time starts after email delivery succeeds" do
    started_at = Time.current.change(usec: 0)
    test = self
    delayed_mailer = Object.new
    delayed_mailer.define_singleton_method(:files_ready) { self }
    delayed_mailer.define_singleton_method(:deliver_now) { test.travel 2.minutes }
    original_with = DeliveryMailer.method(:with)
    DeliveryMailer.define_singleton_method(:with) { |**| delayed_mailer }

    DeliveryEmailJob.perform_now(@delivery)

    assert_operator @delivery.reload.published_at, :>=, started_at + 2.minutes
    assert_equal @delivery.published_at + Send::ACCESS_LIFETIME, @delivery.access_expires_at
  ensure
    travel_back
    DeliveryMailer.define_singleton_method(:with, original_with) if original_with
  end

  test "rolls access rotation back when email delivery fails" do
    original_token = @delivery.issue_access_token!
    @delivery.record_event!(:sent)
    failing_mailer = Object.new
    failing_mailer.define_singleton_method(:files_ready) { raise "SMTP failed" }
    original_with = DeliveryMailer.method(:with)
    DeliveryMailer.define_singleton_method(:with) { |**| failing_mailer }

    assert_raises(RuntimeError) { DeliveryAccessEmailJob.new.perform(@delivery) }

    assert @delivery.reload.access_token_valid?(original_token)
    assert_equal "sent", @delivery.reload.status
    assert @delivery.email_status_failed?
  ensure
    DeliveryMailer.define_singleton_method(:with, original_with) if original_with
  end

  test "marks email failed after retries are exhausted" do
    failing_mailer = Object.new
    failing_mailer.define_singleton_method(:files_ready) { raise Net::SMTPServerBusy, "SMTP busy" }
    original_with = DeliveryMailer.method(:with)
    DeliveryMailer.define_singleton_method(:with) { |**| failing_mailer }

    perform_enqueued_jobs { DeliveryEmailJob.perform_later(@delivery) }

    assert @delivery.reload.email_status_failed?
    assert_nil @delivery.status
    assert_nil @delivery.published_at
  ensure
    DeliveryMailer.define_singleton_method(:with, original_with) if original_with
  end
end
