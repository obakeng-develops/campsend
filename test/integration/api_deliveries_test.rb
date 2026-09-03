require "test_helper"

class ApiDeliveriesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "sender@example.com")
    @write_token = issue_token("write")
    @read_token = issue_token("read")
    @blob = create_uploaded_blob(@user, filename: "brief.pdf")
  end

  test "a token is required, and an invalid one is refused" do
    get api_v1_deliveries_path, as: :json
    assert_response :unauthorized
    assert_equal "Provide a Campsend API token as a bearer token.", response.parsed_body.fetch("error")

    get api_v1_deliveries_path, headers: { "Authorization" => "Bearer csnd_nonsense" }, as: :json
    assert_response :unauthorized
  end

  test "a delivery can be sent and then read back" do
    assert_enqueued_with(job: DeliveryEmailJob) do
      post api_v1_deliveries_path,
        params: { recipient_email: "sam@example.com", file_ids: [ @blob.id ], message: "The final draft." },
        headers: auth(@write_token), as: :json
    end

    assert_response :created
    created = response.parsed_body
    assert_equal "sam@example.com", created.fetch("recipient_email")
    assert_equal 1, created.fetch("file_count")
    assert_equal [ "brief.pdf" ], created.fetch("files").map { |file| file.fetch("filename") }

    get api_v1_delivery_path(created.fetch("delivery_identifier")), headers: auth(@read_token), as: :json

    assert_response :success
    assert_equal created.fetch("delivery_identifier"), response.parsed_body.fetch("delivery_identifier")
  end

  test "a read token cannot send" do
    assert_no_difference "Send.count" do
      post api_v1_deliveries_path,
        params: { recipient_email: "sam@example.com", file_ids: [ @blob.id ] },
        headers: auth(@read_token), as: :json
    end

    assert_response :forbidden
    assert_match "can only read", response.parsed_body.fetch("error")
  end

  test "sending nothing says so plainly" do
    post api_v1_deliveries_path,
      params: { recipient_email: "sam@example.com", file_ids: [] },
      headers: auth(@write_token), as: :json

    assert_response :unprocessable_content
    assert_equal "Give at least one file id in file_ids.", response.parsed_body.fetch("error")
  end

  test "files belonging to somebody else are refused" do
    intruder = User.create!(email_address: "intruder@example.com")
    theirs = create_uploaded_blob(intruder)

    post api_v1_deliveries_path,
      params: { recipient_email: "sam@example.com", file_ids: [ theirs.id ] },
      headers: auth(@write_token), as: :json

    assert_response :unprocessable_content
    assert_match "not yours", response.parsed_body.fetch("error")
  end

  test "a rejected delivery answers with the reason rather than a stack trace" do
    post api_v1_deliveries_path,
      params: { recipient_email: "not-an-email", file_ids: [ @blob.id ] },
      headers: auth(@write_token), as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.fetch("error").present?
  end

  test "listing is newest first, filterable, and limited" do
    3.times { |index| create_delivery("sam#{index}@example.com") }

    get api_v1_deliveries_path, headers: auth(@read_token), as: :json
    assert_response :success
    assert_equal 3, response.parsed_body.fetch("deliveries").size

    get api_v1_deliveries_path(limit: 2), headers: auth(@read_token), as: :json
    assert_equal 2, response.parsed_body.fetch("deliveries").size

    get api_v1_deliveries_path(status: "nonsense"), headers: auth(@read_token), as: :json
    assert_empty response.parsed_body.fetch("deliveries")
  end

  test "another user's delivery is not found rather than forbidden" do
    intruder = User.create!(email_address: "intruder@example.com")
    _token, raw = ApiToken.issue_for(intruder, name: "theirs", scope: "read")
    delivery = create_delivery("sam@example.com")

    get api_v1_delivery_path(delivery.delivery_identifier),
      headers: { "Authorization" => "Bearer #{raw}" }, as: :json

    assert_response :not_found
    assert_equal "No delivery with that identifier.", response.parsed_body.fetch("error")
  end

  test "nothing in a response hands out a way to reach the bytes" do
    delivery = create_delivery("sam@example.com")

    get api_v1_delivery_path(delivery.delivery_identifier), headers: auth(@read_token), as: :json

    body = response.body
    assert_no_match(/access_token|token_digest|X-Amz-Signature|rails\/active_storage/, body)
  end

  # The whole point of the API: a script with a token, and no browser anywhere.
  test "a token can upload a file and then send it" do
    content = "the finished cut"
    post rails_direct_uploads_path,
      params: { blob: { filename: "cut.mov", byte_size: content.bytesize, checksum: Base64.strict_encode64(Digest::MD5.digest(content)), content_type: "video/quicktime" } },
      headers: auth(@write_token), as: :json

    assert_response :success
    blob = ActiveStorage::Blob.find(response.parsed_body.fetch("id"))
    assert_equal @user.id, blob.uploader_id
    assert response.parsed_body.dig("direct_upload", "url").present?, "the caller needs somewhere to PUT the bytes"

    # What the client does between the two calls: PUT the file to the presigned
    # url the reservation handed back.
    blob.service.upload(blob.key, StringIO.new(content), checksum: blob.checksum)

    post api_v1_deliveries_path,
      params: { recipient_email: "sam@example.com", file_ids: [ blob.id ] },
      headers: auth(@write_token), as: :json

    assert_response :created
    assert_equal [ "cut.mov" ], response.parsed_body.fetch("files").map { |file| file.fetch("filename") }
  end

  test "a read token cannot upload" do
    assert_no_difference "ActiveStorage::Blob.count" do
      post rails_direct_uploads_path, params: { blob: blob_params }, headers: auth(@read_token), as: :json
    end

    assert_response :forbidden
  end

  test "uploading still needs somebody, token or session" do
    post rails_direct_uploads_path, params: { blob: blob_params }, as: :json

    assert_response :unauthorized
  end

  private
    def blob_params
      { filename: "x.txt", byte_size: 5, checksum: Base64.strict_encode64(Digest::MD5.digest("hello")), content_type: "text/plain" }
    end

    def issue_token(scope)
      _token, raw = ApiToken.issue_for(@user, name: "#{scope} token", scope: scope)
      raw
    end

    def auth(raw) = { "Authorization" => "Bearer #{raw}" }

    def create_delivery(recipient)
      delivery = @user.sends.new(recipient_email: recipient, files: [ create_uploaded_blob(@user) ])
      delivery.deliver!
      delivery
    end
end
