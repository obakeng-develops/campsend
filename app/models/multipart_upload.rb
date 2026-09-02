# Uploads a blob in parts, for files larger than the single presigned PUT that
# Active Storage's direct upload issues.
class MultipartUpload
  class NotSupported < StandardError; end
  class SizeMismatch < StandardError; end

  THRESHOLD = 100.megabytes
  BASE_PART_SIZE = 100.megabytes
  PART_LIMIT = 9_000 # S3 and R2 allow 10,000. Leave room.
  URL_TTL = 1.hour

  attr_reader :blob, :upload_id

  class << self
    # A service that fronts several buckets, one per user, answers
    # multipart_service_for instead of exposing a client and bucket of its own.
    def supported?(service)
      service.respond_to?(:multipart_service_for) || (service.respond_to?(:client) && service.respond_to?(:bucket))
    end

    def wanted_for?(byte_size, service)
      byte_size.to_i >= THRESHOLD && supported?(service)
    end

    def start(blob)
      raise NotSupported unless supported?(blob.service)

      response = s3_client(blob).create_multipart_upload(
        bucket: bucket_name(blob), key: blob.key, content_type: blob.content_type
      )
      new(blob, response.upload_id)
    end

    def from_token(token, user:)
      blob_id, upload_id = verifier.verify(token)
      new(ActiveStorage::Blob.find_by!(id: blob_id, uploader_id: user.id), upload_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ActiveRecord::RecordNotFound
    end

    # An upload the client never completed or aborted keeps billing for its
    # parts, and the blob it reserved is purged after a day regardless.
    # Takes one bucket. A service fronting many has to sweep each of them, so it
    # calls this per bucket rather than passing itself.
    def abort_abandoned!(service = ActiveStorage::Blob.service, older_than: 1.day.ago)
      return 0 unless service.respond_to?(:client) && service.respond_to?(:bucket)

      client = service.client.client
      bucket = service.bucket.name
      aborted = 0
      markers = {}

      loop do
        listing = client.list_multipart_uploads(bucket: bucket, **markers)
        listing.uploads.each do |upload|
          next if upload.initiated > older_than

          client.abort_multipart_upload(bucket: bucket, key: upload.key, upload_id: upload.upload_id)
          aborted += 1
        end
        break unless listing.is_truncated

        markers = { key_marker: listing.next_key_marker, upload_id_marker: listing.next_upload_id_marker }
      end

      aborted
    end

    def verifier
      Rails.application.message_verifier("multipart_upload")
    end

    def s3_service_for(blob)
      service = blob.service
      service.respond_to?(:multipart_service_for) ? service.multipart_service_for(blob.key) : service
    end

    def s3_client(blob)
      s3_service_for(blob).client.client
    end

    def bucket_name(blob)
      s3_service_for(blob).bucket.name
    end
  end

  def initialize(blob, upload_id)
    @blob = blob
    @upload_id = upload_id
  end

  def token
    self.class.verifier.generate([ blob.id, upload_id ])
  end

  def part_size
    [ BASE_PART_SIZE, (blob.byte_size.to_f / PART_LIMIT).ceil ].max
  end

  def part_count
    (blob.byte_size.to_f / part_size).ceil
  end

  def presign_parts(numbers)
    presigner = Aws::S3::Presigner.new(client: s3_client)
    numbers.map do |number|
      {
        part_number: number,
        url: presigner.presigned_url(
          :upload_part, bucket: bucket_name, key: blob.key,
          upload_id: upload_id, part_number: number, expires_in: URL_TTL.to_i
        )
      }
    end
  end

  # Unlike a single PUT, a multipart upload can exceed the size it reserved.
  def complete!(parts)
    s3_client.complete_multipart_upload(
      bucket: bucket_name, key: blob.key, upload_id: upload_id,
      multipart_upload: { parts: parts.map { |part| { part_number: part.fetch(:part_number), etag: part.fetch(:etag) } } }
    )

    return true if assembled_byte_size == blob.byte_size

    blob.purge
    raise SizeMismatch, "The uploaded file did not match the size it reserved."
  end

  def abort!
    s3_client.abort_multipart_upload(bucket: bucket_name, key: blob.key, upload_id: upload_id)
  end

  def assembled_byte_size
    s3_client.head_object(bucket: bucket_name, key: blob.key).content_length
  end

  private
    def s3_client
      self.class.s3_client(blob)
    end

    def bucket_name
      self.class.bucket_name(blob)
    end
end
