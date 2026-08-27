class Api::V1::DirectUploadsController < ActiveStorage::DirectUploadsController
  include Authentication
  rate_limit to: 60, within: 1.hour, by: -> { current_user&.id || request.remote_ip }

  def create
    if blob_args[:byte_size].to_i > Send::MAX_SEND_SIZE
      return render json: { error: "File exceeds Campsend's 2 GB limit." }, status: :content_too_large
    end

    blob = current_user.reserve_blob!(**blob_args)
    first_delivery = !current_user.sends.exists?
    WideEvent.add(blob_id: blob.id, upload_bytes: blob.byte_size, first_delivery:, upload_operation: "reserved")
    render json: direct_upload_json(blob)
  rescue User::InvalidUploadSize => error
    render json: { error: error.message }, status: :bad_request
  rescue Campsend::Policy::Denied => error
    WideEvent.add(outcome: error.outcome)
    AuditEvent.record!(action: "file.uploaded", outcome: "denied", denial_reason: error.outcome)
    render json: { error: error.message }, status: :unprocessable_content
  end

  private
    def require_authentication
      render json: { error: "Sign in to upload files." }, status: :unauthorized unless authenticated?
    end
end
