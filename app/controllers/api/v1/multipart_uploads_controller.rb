# Presigns, completes and aborts a multipart upload the browser is running.
#
# The reservation that started the upload lives in Api::V1::DirectUploadsController,
# which is where the size and storage limits are enforced. Nothing here reserves
# anything, so nothing here needs to ask the policy again.
class Api::V1::MultipartUploadsController < ApplicationController
  # A window at a time. Wide enough that the browser is not asking constantly,
  # narrow enough that URLs cannot go stale waiting their turn.
  MAX_PARTS_PER_REQUEST = 100

  rate_limit to: 600, within: 1.hour, by: -> { current_user.id }
  before_action :set_upload

  def parts
    numbers = Array(params[:part_numbers]).map(&:to_i)
    unless numbers.size.between?(1, MAX_PARTS_PER_REQUEST)
      return render json: { error: "Ask for between 1 and #{MAX_PARTS_PER_REQUEST} parts at a time." }, status: :bad_request
    end
    # Refused rather than filtered. A client that asks for a part that cannot
    # exist has miscounted, and handing back a short list would hide that until
    # the upload failed to assemble.
    unless numbers.all? { |number| number.between?(1, @upload.part_count) }
      return render json: { error: "This upload has #{@upload.part_count} parts." }, status: :bad_request
    end

    render json: { parts: @upload.presign_parts(numbers) }
  end

  def complete
    @upload.complete!(completed_parts)
    WideEvent.add(blob_id: @upload.blob.id, upload_bytes: @upload.blob.byte_size, upload_operation: "multipart_completed", part_count: @upload.part_count)
    head :no_content
  rescue MultipartUpload::SizeMismatch => error
    WideEvent.add(blob_id: @upload.blob.id, outcome: "multipart_size_mismatch")
    AuditEvent.record!(action: "file.uploaded", outcome: "denied", denial_reason: "multipart_size_mismatch")
    render json: { error: error.message }, status: :unprocessable_content
  end

  def abort
    @upload.abort!
    @upload.blob.purge
    WideEvent.add(blob_id: @upload.blob.id, upload_operation: "multipart_aborted")
    head :no_content
  end

  private
    def set_upload
      @upload = MultipartUpload.from_token(params[:token].to_s, user: current_user)
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Upload not found." }, status: :not_found
    end

    # Order matters to S3: the parts must arrive sorted by part number or the
    # object assembles wrong.
    def completed_parts
      Array(params[:parts]).map { |part|
        { part_number: part[:part_number].to_i, etag: part[:etag].to_s }
      }.sort_by { |part| part[:part_number] }
    end
end
