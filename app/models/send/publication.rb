# Whether a delivery has gone out, is waiting to, or never will.
module Send::Publication
  extend ActiveSupport::Concern

  included do
    validate :scheduled_at_is_future, if: :will_save_change_to_scheduled_at?
    validate :publication_state_is_consistent
  end

  def published?
    published_at.present?
  end

  def canceled?
    canceled_at.present?
  end

  def publication_pending?
    !published? && !canceled?
  end

  def scheduled?
    publication_pending? && scheduled_at.present?
  end

  def cancel!
    with_lock do
      return false unless publication_pending?

      update!(canceled_at: Time.current)
      AuditEvent.record!(action: "delivery.canceled", target: self)
    end
  end

  def update_before_publication(attributes)
    with_lock do
      return false unless publication_pending?

      update(attributes)
    end
  end

  private
    def scheduled_at_is_future
      errors.add(:scheduled_at, "must be in the future") if scheduled_at.present? && scheduled_at <= Time.current
    end

    def publication_state_is_consistent
      errors.add(:base, "A delivery cannot be published and canceled") if published? && canceled?
    end
end
