class Api::V1::DirectUploadsController < ActiveStorage::DirectUploadsController
  include Authentication
  rate_limit to: 60, within: 1.hour, by: -> { current_user&.id || request.remote_ip }

  def create
    if blob_args[:byte_size].to_i > Send.max_size_for(current_user)
      return render json: { error: "File exceeds Campsend's #{Send.human_max_size_for(current_user)} limit." }, status: :content_too_large
    end

    blob = current_user.reserve_blob!(**blob_args)
    first_delivery = !current_user.sends.exists?
    WideEvent.add(blob_id: blob.id, upload_bytes: blob.byte_size, first_delivery:, upload_operation: "reserved")
    render json: direct_upload_json(blob).merge(multipart_json(blob))
  rescue User::InvalidUploadSize => error
    render json: { error: error.message }, status: :bad_request
  rescue Campsend::Policy::Denied => error
    WideEvent.add(outcome: error.outcome)
    AuditEvent.record!(action: "file.uploaded", outcome: "denied", denial_reason: error.outcome)
    render json: { error: error.message }, status: :unprocessable_content
  end

  private
    # A file too big for one PUT gets the multipart plan instead. The single-PUT
    # url that direct_upload_json builds is still in the response and still
    # valid; the client ignores it when this key is present.
    def multipart_json(blob)
      return {} unless MultipartUpload.wanted_for?(blob.byte_size, blob.service)

      upload = MultipartUpload.start(blob)
      WideEvent.add(upload_operation: "multipart_started", part_count: upload.part_count)
      {
        multipart: {
          token: upload.token,
          part_size: upload.part_size,
          part_count: upload.part_count,
          parts_url: api_v1_multipart_upload_parts_path,
          complete_url: api_v1_multipart_upload_complete_path,
          abort_url: api_v1_multipart_upload_abort_path
        }
      }
    end

    def require_authentication
      render json: { error: "Sign in to upload files." }, status: :unauthorized unless authenticated?
    end
end
