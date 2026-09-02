class User < ApplicationRecord
  class InvalidUploadSize < StandardError; end
  class UploadTooLarge < StandardError; end

  has_many :login_tokens, dependent: :delete_all
  has_many :api_tokens, dependent: :delete_all
  has_many :google_drive_imports, dependent: :delete_all
  has_many :sends, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :received_sends, class_name: "Send", foreign_key: :recipient_email, primary_key: :email_address
  has_many :uploaded_blobs, class_name: "ActiveStorage::Blob", foreign_key: :uploader_id, inverse_of: false
  has_many_attached :files

  normalizes :email_address, with: ->(email) { email.strip.downcase.sub(/\+[^@]+/, "") }

  validates :email_address, presence: true,
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { case_sensitive: false }
  def storage_used
    uploaded_blobs.sum(:byte_size)
  end

  def reserve_blob!(**attributes)
    with_lock do
      byte_size = attributes.fetch(:byte_size).to_i
      raise InvalidUploadSize, "File size cannot be negative." if byte_size.negative?
      raise UploadTooLarge, "File exceeds Campsend's #{Send.human_max_file_size_for(self)} limit." if byte_size > Send.max_file_size_for(self)

      Campsend.policy.admit_storage(user: self, byte_size:) do
        key = "#{Campsend.policy.storage_key_prefix_for(user: self)}/#{ActiveStorage::Blob.generate_unique_secure_token}"
        attributes[:service_name] = Campsend.policy.storage_service_name_for(user: self)
        ActiveStorage::Blob.create_before_direct_upload!(key: key, **attributes).tap do |blob|
          blob.update!(uploader_id: id)
        end
      end
    end
  end

  def retain_files(blobs)
    owned_blobs = blobs.select { |blob| blob.uploader_id == id }
    existing_ids = files.blobs.where(id: owned_blobs.map(&:id)).ids
    files.attach(owned_blobs.reject { |blob| blob.id.in?(existing_ids) })
  end
end
