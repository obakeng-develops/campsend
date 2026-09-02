require "test_helper"

class MultipartUploadTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sender@example.com")
    @service = ActiveStorage::Blob.services.fetch("s3_test")
  end

  test "only an S3-backed service can do this, so Disk keeps the single PUT path" do
    assert MultipartUpload.supported?(@service)
    assert_not MultipartUpload.supported?(ActiveStorage::Blob.services.fetch("test"))
    assert_not MultipartUpload.wanted_for?(1.terabyte, ActiveStorage::Blob.services.fetch("test"))
  end

  test "small files are left alone" do
    assert_not MultipartUpload.wanted_for?(MultipartUpload::THRESHOLD - 1, @service)
    assert MultipartUpload.wanted_for?(MultipartUpload::THRESHOLD, @service)
  end

  test "part sizing stays inside what S3 allows at any scale" do
    { 500.megabytes => 5, 40.gigabytes => 410, 1.terabyte => 9000, 5.terabytes => 9000 }.each do |byte_size, expected_parts|
      upload = MultipartUpload.new(blob(byte_size:), "u")

      assert_equal expected_parts, upload.part_count, "#{byte_size} bytes"
      assert upload.part_size >= 5.megabytes, "part size must clear the 5 MiB minimum"
      assert upload.part_count <= 10_000, "part count must clear the 10,000 ceiling"
    end
  end

  test "a token resolves back to its own upload" do
    upload = MultipartUpload.new(blob, "upload-id")

    resolved = MultipartUpload.from_token(upload.token, user: @user)

    assert_equal upload.blob.id, resolved.blob.id
    assert_equal "upload-id", resolved.upload_id
  end

  test "a token does not resolve for anyone else" do
    upload = MultipartUpload.new(blob, "upload-id")
    intruder = User.create!(email_address: "intruder@example.com")

    assert_raises(ActiveRecord::RecordNotFound) { MultipartUpload.from_token(upload.token, user: intruder) }
  end

  test "a forged token does not resolve" do
    assert_raises(ActiveRecord::RecordNotFound) { MultipartUpload.from_token("not-a-token", user: @user) }
  end

  test "completing verifies the assembled object against what was reserved" do
    reserved = blob(byte_size: 200.megabytes)
    upload = MultipartUpload.new(reserved, "upload-id")
    stub(:complete_multipart_upload, {})
    stub(:head_object, { content_length: 200.megabytes })

    assert upload.complete!([ { part_number: 1, etag: "a" }, { part_number: 2, etag: "b" } ])
  end

  test "an object larger than its reservation is thrown away" do
    reserved = blob(byte_size: 1.megabyte)
    upload = MultipartUpload.new(reserved, "upload-id")
    stub(:complete_multipart_upload, {})
    stub(:head_object, { content_length: 10.gigabytes })

    assert_raises(MultipartUpload::SizeMismatch) do
      upload.complete!([ { part_number: 1, etag: "a" } ])
    end
    assert_not ActiveStorage::Blob.exists?(reserved.id)
  end

  private
    def blob(byte_size: 500.megabytes)
      ActiveStorage::Blob.create_before_direct_upload!(
        key: "users/#{@user.id}/blobs/#{ActiveStorage::Blob.generate_unique_secure_token}",
        filename: "master.mov", byte_size: byte_size,
        checksum: Base64.strict_encode64(Digest::MD5.digest("x")),
        content_type: "video/quicktime", service_name: "s3_test"
      ).tap { |blob| blob.update!(uploader_id: @user.id) }
    end

    def stub(operation, response)
      @service.client.client.stub_responses(operation, response)
    end
end
