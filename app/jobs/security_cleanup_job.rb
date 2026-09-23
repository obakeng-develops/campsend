class SecurityCleanupJob < ApplicationJob
  HELD_LIFETIME = LoginToken::CONFIRMATION_LIFETIME

  def perform
    LoginToken.where("expires_at < ? OR used_at < ?", Time.current, 1.day.ago).delete_all
    WideEvent.add(held_deliveries_removed: remove_stale_held_deliveries, unverified_users_removed: remove_stale_unverified_users)
    GoogleDriveImport.where(status: %w[completed failed], updated_at: ...1.day.ago).delete_all
    # Before the purge, so a completion racing this cannot land an object after
    # the purge has already looked for one.
    WideEvent.add(multipart_uploads_aborted: MultipartUpload.abort_abandoned!)
    ActiveStorage::Blob.unattached.where(created_at: ...1.day.ago).find_each(&:purge)
    AuditEvent.purge_expired!
  end

  private
    def remove_stale_held_deliveries
      stale = Send.email_status_held.where(created_at: ...HELD_LIFETIME.ago)
      removed = stale.count
      stale.find_each(&:destroy!)
      removed
    end

    # Sends first, so their attachments are gone before the blobs behind them
    # are purged; then the reserved blobs, which the users foreign key would
    # otherwise refuse to orphan.
    def remove_stale_unverified_users
      stale = User.where(verified_at: nil, created_at: ...HELD_LIFETIME.ago)
      removed = stale.count
      stale.find_each do |user|
        user.sends.find_each(&:destroy!)
        user.files.each(&:purge)
        user.uploaded_blobs.find_each(&:purge)
        user.destroy!
      end
      removed
    end
end
