# How a delivery is addressed in a URL. A slug is optional, and once the
# delivery is published it can never change or be reused, because the link is
# already in someone's inbox.
module Send::Slug
  extend ActiveSupport::Concern

  included do
    normalizes :slug, with: ->(slug) { slug.strip.downcase.presence }

    validates :slug,
      length: { maximum: 100 },
      format: { with: Send::SLUG_FORMAT },
      exclusion: { in: Send::RESERVED_SLUGS },
      uniqueness: true,
      allow_nil: true
    validate :published_slug_is_immutable, if: :will_save_change_to_slug?

    before_destroy :retain_published_slug
  end

  class_methods do
    def find_by_delivery_identifier(identifier)
      find_by(slug: identifier) || find_by(public_id: identifier)
    end

    def find_by_delivery_identifier!(identifier)
      find_by_delivery_identifier(identifier) || raise(ActiveRecord::RecordNotFound)
    end
  end

  def delivery_identifier
    slug.presence || public_id
  end

  def audit_label
    "#{delivery_identifier} to #{recipient_email}"
  end

  private
    def published_slug_is_immutable
      errors.add(:slug, "cannot change after publication") if published_at_in_database.present?
    end

    def retain_published_slug
      return unless published? && slug.present?

      errors.add(:base, "Published delivery links cannot be deleted")
      throw :abort
    end
end
