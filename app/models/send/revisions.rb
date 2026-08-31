# The files attached to a delivery, and the append-only history of replacing
# them. Files on a published delivery are immutable; a change appends a revision
# and the recipient's existing link starts serving it.
module Send::Revisions
  extend ActiveSupport::Concern

  included do
    has_many :delivery_revisions, -> { order(number: :asc) }, inverse_of: :delivery, dependent: :destroy, autosave: true
    has_one :latest_revision, -> { order(number: :desc) }, class_name: "DeliveryRevision", inverse_of: :delivery

    scope :with_attached_files, -> { includes(latest_revision: { files_attachments: :blob }) }

    validate :revision_is_valid
  end

  def files
    files_revision.files
  end

  def files=(attachables)
    raise ActiveRecord::ReadOnlyRecord, "Published delivery files are immutable" if persisted?

    files.attach(attachables)
  end

  def replace_file!(attachment_id, replacement_blob)
    raise ActiveRecord::ReadOnlyRecord, "Collection deliveries follow their collection" if collection_id?

    with_lock do
      current = delivery_revisions.includes(files_attachments: :blob).order(number: :desc).first!
      replaced = current.files.attachments.find(attachment_id)
      blobs = current.files.attachments.map { |attachment| attachment == replaced ? replacement_blob : attachment.blob }
      append_revision!(blobs:).tap do
        AuditEvent.record!(
          action: "delivery.file_replaced",
          target: self,
          changed_fields: { "filename" => [ replaced.blob.filename.to_s, replacement_blob.filename.to_s ] }
        )
      end
    end
  end

  def revise_from_collection!(source)
    raise ActiveRecord::RecordNotFound unless collection_id == source.id && user_id == source.user_id

    with_lock do
      append_revision!(blobs: source.blobs.to_a, collection_name: source.name)
    end
  end

  private
    def files_revision
      if new_record?
        @initial_revision ||= delivery_revisions.build(number: 1, collection_name: collection&.name)
        return @initial_revision
      end

      latest_revision
    end

    def append_revision!(blobs:, collection_name: nil)
      current = delivery_revisions.reorder(number: :desc).first!
      delivery_revisions.create!(number: current.number + 1, files: blobs, collection_name:).tap do
        association(:latest_revision).reset
      end
    end

    def revision_is_valid
      files_revision.errors.each { |error| errors.import(error) } unless files_revision.valid?
    end
end
