require "base64"
require "digest"
require "tempfile"

class GoogleDriveImportJob < ApplicationJob
  PermanentError = GoogleDrive::Client::PermanentError
  TransientError = GoogleDrive::Client::TransientError
  NETWORK_ERRORS = GoogleDrive::Client::NETWORK_ERRORS

  retry_on TransientError, *NETWORK_ERRORS, wait: 10.seconds, attempts: 3 do |job, _error|
    job.arguments.first.tap do |drive_import|
      drive_import.blob&.purge
      drive_import.fail!("Google Drive didn't finish the import. Try again.")
    end
  end

  # The client is a keyword default so a test can hand in its own, matching how
  # the managed distribution injects GitHubClient into FeedbackIssueJob.
  def perform(drive_import, encrypted_token, client: GoogleDrive::Client.new)
    WideEvent.add(user_id: drive_import.user_id, import_id: drive_import.id, import_provider: "google_drive")
    return if drive_import.status == "completed"

    drive_import.update!(status: "importing", error: nil)
    if drive_import.blob&.service&.exist?(drive_import.blob.key)
      finish_import(drive_import)
      return
    end

    token = GoogleDrive::Token.decrypt(encrypted_token)
    metadata = client.metadata(drive_import.google_file_id, token:, resource_key: drive_import.resource_key)
    validate_metadata!(drive_import, metadata)
    blob = drive_import.blob || reserve_blob(drive_import, metadata)
    drive_import.update!(blob: blob, filename: filename(metadata))
    WideEvent.add(import_id: drive_import.id, import_bytes: Integer(metadata.fetch("size")))

    download(drive_import, metadata, token, client) do |file, checksum|
      blob.update!(checksum: checksum)
      blob.upload_without_unfurling(file)
    end
    finish_import(drive_import)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    fail_import(drive_import, "Google access expired. Open Drive and try again.")
  rescue PermanentError => error
    fail_import(drive_import, error.message)
  rescue TransientError, *NETWORK_ERRORS
    raise
  rescue StandardError
    fail_import(drive_import, "The Google Drive import failed. Try again.")
    raise
  end

  private
    def validate_metadata!(drive_import, metadata)
      mime_type = metadata.fetch("mimeType", "")
      raise PermanentError, "Google Docs, Sheets, and Slides aren't supported yet." if mime_type.start_with?("application/vnd.google-apps.")
      raise PermanentError, "Google Drive doesn't allow this file to be downloaded." unless metadata.dig("capabilities", "canDownload")

      size = Integer(metadata["size"], exception: false)
      raise PermanentError, "Google Drive didn't provide this file's size." unless size
      raise PermanentError, "This file is larger than Campsend's #{Send.human_max_size_for(drive_import.user)} limit." if size > Send.max_size_for(drive_import.user)
      raise PermanentError, "Google Drive didn't provide this file's name." if metadata["name"].blank?
      if metadata["md5Checksum"].present? && !metadata["md5Checksum"].match?(/\A[0-9a-f]{32}\z/i)
        raise PermanentError, "Google Drive returned an invalid file checksum."
      end
    end

    def reserve_blob(drive_import, metadata)
      checksum = checksum_from_hex(metadata["md5Checksum"])
      drive_import.user.reserve_blob!(
        filename: filename(metadata),
        byte_size: Integer(metadata.fetch("size")),
        checksum: checksum,
        content_type: metadata["mimeType"]
      )
    rescue Campsend::Policy::Denied => error
      WideEvent.add(outcome: error.outcome)
      raise PermanentError, error.message
    end

    # Streams to a tempfile, counting bytes and hashing as it goes, so a file
    # that changed underneath us fails before it reaches storage.
    def download(drive_import, metadata, token, client)
      expected_size = Integer(metadata.fetch("size"))
      expected_checksum = checksum_from_hex(metadata["md5Checksum"])
      file = Tempfile.new([ "campsend-drive-", ".download" ], binmode: true)
      digest = Digest::MD5.new
      bytes = 0

      client.download(drive_import.google_file_id, token:, resource_key: drive_import.resource_key) do |chunk|
        bytes += chunk.bytesize
        raise PermanentError, "The downloaded file exceeded Campsend's #{Send.human_max_size_for(drive_import.user)} limit." if bytes > Send.max_size_for(drive_import.user)

        digest.update(chunk)
        file.write(chunk)
      end

      raise PermanentError, "Google Drive changed the file while it was importing." unless bytes == expected_size

      checksum = Base64.strict_encode64(digest.digest)
      raise PermanentError, "Google Drive changed the file while it was importing." if expected_checksum && checksum != expected_checksum

      file.rewind
      yield file, checksum
    ensure
      file&.close!
    end

    def checksum_from_hex(checksum)
      Base64.strict_encode64([ checksum ].pack("H*")) if checksum.present?
    end

    def filename(metadata)
      metadata.fetch("name").delete("\0").truncate(255)
    end

    def finish_import(drive_import)
      drive_import.user.retain_files([ drive_import.blob ])
      drive_import.update!(status: "completed", error: nil)
      WideEvent.add(import_id: drive_import.id, import_status: "completed")
    end

    def fail_import(drive_import, message)
      drive_import.blob&.purge
      drive_import.fail!(message)
      WideEvent.add(import_id: drive_import.id, import_status: "failed", import_error: message.to_s.truncate(200))
    end
end
