# A multipart upload in flight against an S3-compatible service.
#
# Active Storage's direct upload issues one presigned PUT, and S3 and R2 refuse
# a single PUT above 4.995 GiB, so that is the ceiling for anything the browser
# uploads. This splits the transfer into parts the browser presigns and sends
# itself, which is what lets a delivery hold more than one PUT can carry.
#
# There is no table. The upload id travels to the client inside a signed token
# and comes back on every call, and an abandoned upload is found by asking the
# service, which already knows, rather than by keeping a second copy that can
# disagree with it.
class MultipartUpload
  class NotSupported < StandardError; end
  class SizeMismatch < StandardError; end

  # Below this one PUT is simpler and a round trip cheaper. Matches the default
  # Rails uses for the server-side equivalent.
  THRESHOLD = 100.megabytes
  # S3 and R2 allow 10,000 parts and require at least 5 MiB for every part but
  # the last. Dividing by 9,000 keeps the count clear of the ceiling, and the
  # floor keeps parts far clear of the minimum.
  BASE_PART_SIZE = 100.megabytes
  PART_LIMIT = 9_000
  # Long enough that a window of parts cannot expire while earlier parts in the
  # same window are still going, short enough that a leaked URL goes stale.
  URL_TTL = 1.hour

  attr_reader :blob, :upload_id

  class << self
    # An S3-backed service exposes an Aws::S3::Resource and a bucket. Disk does
    # not, which is why development and test keep the single PUT path without
    # any conditional in the views.
    def supported?(service)
      service.respond_to?(:client) && service.respond_to?(:bucket)
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

    # Resolves a token back to an upload, scoped to the caller. A token for
    # someone else's blob does not resolve, so it reads as missing rather than
    # forbidden.
    def from_token(token, user:)
      blob_id, upload_id = verifier.verify(token)
      blob = ActiveStorage::Blob.find_by!(id: blob_id, uploader_id: user.id)
      new(blob, upload_id)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ActiveRecord::RecordNotFound
    end

    def verifier
      Rails.application.message_verifier("multipart_upload")
    end

    def s3_client(blob)
      blob.service.client.client
    end

    def bucket_name(blob)
      blob.service.bucket.name
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

  # A window rather than every part at once, so a 40 GB upload does not need
  # thousands of URLs up front and none of them expires while it waits.
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

  # The reservation trusts a client-supplied byte_size. One PUT is self
  # limiting, but a multipart upload is not, so the assembled object is measured
  # against what was reserved and thrown away if it does not match.
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
