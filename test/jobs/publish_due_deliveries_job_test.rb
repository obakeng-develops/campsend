require "test_helper"

class PublishDueDeliveriesJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "wakes only pending deliveries that are due" do
    user = User.create!(email_address: "sender@example.com")
    due = create_delivery(user)
    future = create_delivery(user, scheduled_at: 2.hours.from_now)
    canceled = create_delivery(user, scheduled_at: 2.hours.from_now)
    canceled.cancel!
    failed = create_delivery(user)
    failed.update!(email_status: "failed")
    published = create_delivery(user)
    published.issue_access_token!
    published.record_event!(:sent)
    held = create_delivery(user)
    held.update!(email_status: "held")

    assert_enqueued_with(job: DeliveryEmailJob, args: [ due ]) do
      PublishDueDeliveriesJob.perform_now
    end
    enqueued_ids = enqueued_jobs.filter_map { |job| job.fetch(:args).first.dig("_aj_globalid") if job.fetch(:job) == DeliveryEmailJob }
    assert_equal [ due.to_global_id.to_s ], enqueued_ids
    assert_not_includes enqueued_ids, future.to_global_id.to_s
    assert_not_includes enqueued_ids, held.to_global_id.to_s

    assert_no_enqueued_jobs only: DeliveryEmailJob do
      PublishDueDeliveriesJob.perform_now
    end

    travel 6.minutes do
      assert_enqueued_with(job: DeliveryEmailJob, args: [ due ]) do
        PublishDueDeliveriesJob.perform_now
      end
    end
  end

  private
    def create_delivery(user, scheduled_at: nil)
      user.sends.new(recipient_email: "sam@example.com", scheduled_at: scheduled_at).tap do |delivery|
        delivery.files.attach(create_uploaded_blob(user))
        delivery.save!
      end
    end
end
