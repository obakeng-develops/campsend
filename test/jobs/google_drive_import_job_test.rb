require "test_helper"

class GoogleDriveImportJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sender@example.com")
    @drive_import = @user.google_drive_imports.create!(google_file_id: "drive-file-123", filename: "Report.pdf")
    @token = GoogleDrive::Token.encrypt("short-lived-token")
  end

  test "stores a verified Drive snapshot in My Files" do
    content = "private report"

    perform(client: stubbed_client(content:))

    assert_equal "completed", @drive_import.reload.status
    assert_equal [ @drive_import.blob_id ], @user.files.blobs.ids
    assert_equal content, @drive_import.blob.download
    assert_match %r{\Ausers/#{@user.id}/blobs/[a-z0-9]{28}\z}, @drive_import.blob.key
  end

  test "rejects native Google Workspace documents" do
    perform(client: stubbed_client(metadata: metadata.merge("mimeType" => "application/vnd.google-apps.document", "size" => nil)))

    assert_equal "failed", @drive_import.reload.status
    assert_match "aren't supported", @drive_import.error
    assert_nil @drive_import.blob
  end

  test "releases reserved storage when verification fails" do
    job = GoogleDriveImportJob.new
    job.define_singleton_method(:download) do |*, **|
      raise GoogleDriveImportJob::PermanentError, "Google Drive changed the file while it was importing."
    end

    job.perform(@drive_import, @token, client: stubbed_client)

    assert_equal "failed", @drive_import.reload.status
    assert_nil @drive_import.blob
    assert_equal 0, @user.storage_used
  end

  test "expires queued Google access tokens" do
    expired_token = travel_to(2.hours.ago) { GoogleDrive::Token.encrypt("expired") }

    perform(client: stubbed_client, encrypted_token: expired_token)

    assert_equal "failed", @drive_import.reload.status
    assert_match "access expired", @drive_import.error
  end

  private
    def perform(client:, encrypted_token: @token)
      GoogleDriveImportJob.new.perform(@drive_import, encrypted_token, client: client)
    end

    # A stand-in for GoogleDrive::Client. The job takes one as a keyword, so the
    # transport can be replaced without reaching into the job's privates.
    def stubbed_client(content: "private report", metadata: nil)
      file_metadata = metadata || self.metadata.merge(
        "size" => content.bytesize.to_s,
        "md5Checksum" => Digest::MD5.hexdigest(content)
      )
      client = Object.new
      client.define_singleton_method(:metadata) { |*, **| file_metadata }
      client.define_singleton_method(:download) do |*, **, &block|
        content.bytes.each_slice(4) { |bytes| block.call(bytes.pack("C*")) }
      end
      client
    end

    def metadata
      {
        "id" => "drive-file-123",
        "name" => "Report.pdf",
        "mimeType" => "application/pdf",
        "capabilities" => { "canDownload" => true }
      }
    end


    def reserve_storage(user, byte_size)
      ActiveStorage::Blob.create_before_direct_upload!(
        filename: "reserved.bin",
        byte_size: byte_size,
        checksum: Base64.strict_encode64(Digest::MD5.digest("reserved")),
        content_type: "application/octet-stream"
      ).update!(uploader_id: user.id)
    end
end
