require "test_helper"

class MultipartUploadFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    sign_in_as(@user)
    @service = ActiveStorage::Blob.services.fetch("s3_test")
  end

  test "a small file is reserved the way it always was" do
    post rails_direct_uploads_path, params: { blob: blob_params(byte_size: 5) }, as: :json

    assert_response :success
    assert response.parsed_body.key?("direct_upload")
    assert_not response.parsed_body.key?("multipart")
  end

  test "Disk keeps the single PUT path however large the file" do
    post rails_direct_uploads_path, params: { blob: blob_params(byte_size: 1.gigabyte) }, as: :json

    assert_response :success
    assert_not response.parsed_body.key?("multipart")
  end

  test "a large file on S3 is reserved with a plan for uploading it in parts" do
    stub(:create_multipart_upload, { upload_id: "upload-id" })

    on_s3 { post rails_direct_uploads_path, params: { blob: blob_params(byte_size: 500.megabytes) }, as: :json }

    assert_response :success
    multipart = response.parsed_body.fetch("multipart")
    assert_equal 104857600, multipart.fetch("part_size")
    assert_equal 5, multipart.fetch("part_count")
    assert_equal api_v1_multipart_upload_parts_path, multipart.fetch("parts_url")
    assert multipart.fetch("token").present?
  end

  test "parts are presigned a window at a time" do
    token = reserve

    post api_v1_multipart_upload_parts_path, params: { token:, part_numbers: [ 1, 2, 3 ] }, as: :json

    assert_response :success
    parts = response.parsed_body.fetch("parts")
    assert_equal [ 1, 2, 3 ], parts.map { |part| part.fetch("part_number") }
    assert parts.all? { |part| part.fetch("url").include?("partNumber=#{part.fetch('part_number')}") }
    assert parts.all? { |part| part.fetch("url").include?("uploadId=upload-id") }
  end

  test "a window beyond the part count or beyond the cap is refused" do
    token = reserve

    post api_v1_multipart_upload_parts_path, params: { token:, part_numbers: [ 99 ] }, as: :json
    assert_response :bad_request

    post api_v1_multipart_upload_parts_path, params: { token:, part_numbers: (1..200).to_a }, as: :json
    assert_response :bad_request
  end

  test "completing assembles the object and checks it against the reservation" do
    token = reserve
    stub(:complete_multipart_upload, {})
    stub(:head_object, { content_length: 500.megabytes })

    post api_v1_multipart_upload_complete_path, params: { token:, parts: [ { part_number: 1, etag: "a" } ] }, as: :json

    assert_response :no_content
  end

  test "an upload larger than its reservation is refused and thrown away" do
    token = reserve
    blob = ActiveStorage::Blob.last
    stub(:complete_multipart_upload, {})
    stub(:head_object, { content_length: 10.gigabytes })

    post api_v1_multipart_upload_complete_path, params: { token:, parts: [ { part_number: 1, etag: "a" } ] }, as: :json

    assert_response :unprocessable_content
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert AuditEvent.exists?(action: "file.uploaded", outcome: "denied", denial_reason: "multipart_size_mismatch")
  end

  test "aborting drops the upload and the reservation" do
    token = reserve
    blob = ActiveStorage::Blob.last
    stub(:abort_multipart_upload, {})

    post api_v1_multipart_upload_abort_path, params: { token: }, as: :json

    assert_response :no_content
    assert_not ActiveStorage::Blob.exists?(blob.id)
  end

  test "another user's token is not found rather than forbidden" do
    token = reserve
    delete session_path
    sign_in_as(User.create!(email_address: "intruder@example.com"))

    post api_v1_multipart_upload_parts_path, params: { token:, part_numbers: [ 1 ] }, as: :json

    assert_response :not_found
  end

  test "signing out ends the upload" do
    token = reserve
    delete session_path

    post api_v1_multipart_upload_parts_path, params: { token:, part_numbers: [ 1 ] }, as: :json

    assert_redirected_to new_session_path
  end

  private
    def sign_in_as(user)
      login_token, raw_token = LoginToken.issue_for(user)
      post consume_sign_in_path(public_id: login_token.public_id), params: { token: raw_token }
    end

    def blob_params(byte_size:)
      {
        filename: "master.mov", byte_size:,
        checksum: Base64.strict_encode64(Digest::MD5.digest("x")),
        content_type: "video/quicktime"
      }
    end

    def stub(operation, response)
      @service.client.client.stub_responses(operation, response)
    end

    # The reservation endpoint reads the default service, so a test that wants
    # the multipart branch has to make the default one that supports it.
    def on_s3
      previous = ActiveStorage::Blob.service
      ActiveStorage::Blob.service = @service
      yield
    ensure
      ActiveStorage::Blob.service = previous
    end

    def reserve
      stub(:create_multipart_upload, { upload_id: "upload-id" })
      on_s3 { post rails_direct_uploads_path, params: { blob: blob_params(byte_size: 500.megabytes) }, as: :json }
      response.parsed_body.fetch("multipart").fetch("token")
    end
end
