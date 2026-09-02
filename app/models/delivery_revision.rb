class DeliveryRevision < ApplicationRecord
  belongs_to :delivery, class_name: "Send", foreign_key: :send_id, inverse_of: :delivery_revisions
  has_many_attached :files

  validates :number, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :send_id }
  validates :collection_name, length: { maximum: 100 }, allow_nil: true
  validate :files_are_attached
  validate :files_are_within_limits
  validate :files_belong_to_sender

  private
    def files_are_attached
      errors.add(:base, "Choose at least one file.") unless files.attached?
    end

    def files_are_within_limits
      errors.add(:base, "Choose no more than #{Send::MAX_FILES} files.") if files.size > Send::MAX_FILES
      errors.add(:base, "Files must total #{Send.human_max_size_for(delivery&.user)} or less.") if files.sum(&:byte_size) > Send.max_size_for(delivery&.user)
    end

    def files_belong_to_sender
      return unless delivery&.user

      errors.add(:base, "You can only send files you uploaded.") if files.any? { |file| file.blob.uploader_id != delivery.user_id }
    end
end
