require "test_helper"

class MultipartUploadTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "sender@example.com")
    @service = ActiveStorage::Blob.services.fetch("s3_test")
    @requests_before = @service.client.client.api_requests.size
  end

  test "only an S3-backed service can do this, so Disk keeps the single PUT path" do
    assert MultipartUpload.supported?(@service)
    assert_not MultipartUpload.supported?(ActiveStorage::Blob.services.fetch("test"))
    assert_not MultipartUpload.wanted_for?(1.terabyte, ActiveStorage::Blob.services.fetch("test"))
  end

  test "a service fronting one bucket per user can still do multipart" do
    wrapper = Class.new do
      def initialize(inner) = @inner = inner
      def multipart_service_for(_key) = @inner
    end.new(@service)

    assert MultipartUpload.supported?(wrapper)
    assert MultipartUpload.wanted_for?(500.megabytes, wrapper)
  end

  test "a wrapper has no single bucket to reconcile, so it sweeps none" do
    wrapper = Class.new do
      def multipart_service_for(_key) = nil
    end.new

    assert_equal 0, MultipartUpload.abort_abandoned!(wrapper)
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

  test "an upload left in flight past its blob's life is aborted" do
    stub(:list_multipart_uploads, {
      uploads: [
        { key: "stale", upload_id: "u1", initiated: 3.days.ago },
        { key: "fresh", upload_id: "u2", initiated: 10.minutes.ago }
      ],
      is_truncated: false
    })
    stub(:abort_multipart_upload, {})

    assert_equal 1, MultipartUpload.abort_abandoned!(@service)
    assert_equal [ "stale" ], aborted_keys
  end

  test "reconciliation walks past the first page of results" do
    pages = [
      { uploads: [ { key: "one", upload_id: "u1", initiated: 3.days.ago } ], is_truncated: true, next_key_marker: "one", next_upload_id_marker: "u1" },
      { uploads: [ { key: "two", upload_id: "u2", initiated: 3.days.ago } ], is_truncated: false }
    ]
    stub(:list_multipart_uploads, pages)
    stub(:abort_multipart_upload, {})

    assert_equal 2, MultipartUpload.abort_abandoned!(@service)
    assert_equal [ "one", "two" ], aborted_keys
  end

  test "a service that cannot do multipart has nothing to reconcile" do
    assert_equal 0, MultipartUpload.abort_abandoned!(ActiveStorage::Blob.services.fetch("test"))
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

    # The stubbed client lives in the service registry, so it keeps every
    # request the whole file made. Only this test's are interesting.
    def aborted_keys
      @service.client.client.api_requests.drop(@requests_before)
              .select { |request| request[:operation_name] == :abort_multipart_upload }
              .map { |request| request[:params][:key] }
    end
end
