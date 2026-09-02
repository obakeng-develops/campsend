class SecurityCleanupJob < ApplicationJob
  def perform
    LoginToken.where("expires_at < ? OR used_at < ?", Time.current, 1.day.ago).delete_all
    GoogleDriveImport.where(status: %w[completed failed], updated_at: ...1.day.ago).delete_all
    # Before the purge, so a completion racing this cannot land an object after
    # the purge has already looked for one.
    WideEvent.add(multipart_uploads_aborted: MultipartUpload.abort_abandoned!)
    ActiveStorage::Blob.unattached.where(created_at: ...1.day.ago).find_each(&:purge)
    AuditEvent.purge_expired!
  end
end
