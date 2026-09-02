class Collection < ApplicationRecord
  belongs_to :user
  has_many :collection_files, -> { order(:position) }, dependent: :delete_all
  has_many :blobs, through: :collection_files
  has_many :sends

  scope :active, -> { where(removed_at: nil) }

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :user_id, conditions: -> { active } }

  def add_file!(attachment)
    with_lock do
      ensure_active!
      user.with_lock do
        raise ActiveRecord::RecordNotFound unless attachment.name == "files" && user.files.attachments.exists?(attachment.id)

        validate_limits!([ *blobs, attachment.blob ])
        collection_files.create!(user:, blob: attachment.blob, position: collection_files.maximum(:position).to_i + 1)
        reset_files
        refresh_deliveries!
      end
    end
  end

  def remove_file!(collection_file)
    with_lock do
      ensure_active!
      if collection_files.one? && sends.where(canceled_at: nil).exists?
        errors.add(:base, "A delivered collection must keep at least one file.")
        raise ActiveRecord::RecordInvalid, self
      end

      collection_files.find(collection_file.id).destroy!
      reset_files
      refresh_deliveries!
    end
  end

  def rename!(new_name)
    with_lock do
      ensure_active!
      update!(name: new_name)
      refresh_deliveries!
    end
  end

  def remove!
    with_lock do
      ensure_active!
      update!(removed_at: Time.current)
      collection_files.delete_all
      reset_files
    end
  end

  def size_bytes
    blobs.sum(:byte_size)
  end

  private
    def ensure_active!
      raise ActiveRecord::RecordNotFound if removed_at?
    end

    def validate_limits!(candidate_blobs)
      errors.add(:base, "Choose no more than #{Send::MAX_FILES} files.") if candidate_blobs.size > Send::MAX_FILES
      errors.add(:base, "Files must total #{Send.human_max_size_for(user)} or less.") if candidate_blobs.sum(&:byte_size) > Send.max_size_for(user)
      raise ActiveRecord::RecordInvalid, self if errors.any?
    end

    def refresh_deliveries!
      # ponytail: synchronous fan-out keeps updates atomic; use a job if collection delivery counts make requests slow.
      sends.where(canceled_at: nil).order(:id).find_each { |delivery| delivery.revise_from_collection!(self) }
    end

    def reset_files
      association(:collection_files).reset
      association(:blobs).reset
    end
end
