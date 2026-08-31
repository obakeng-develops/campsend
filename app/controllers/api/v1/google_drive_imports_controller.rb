class Api::V1::GoogleDriveImportsController < ApplicationController
  rate_limit to: 20, within: 1.hour, by: -> { current_user&.id || request.remote_ip }

  def create
    files = params.expect(files: [ [ :id, :name, :resource_key ] ])
    token = params.expect(:access_token).to_s
    return render json: { error: "Choose between 1 and #{Send::MAX_FILES} files." }, status: :unprocessable_content if files.empty?
    return render json: { error: "Choose no more than #{Send::MAX_FILES} files." }, status: :unprocessable_content if files.size > Send::MAX_FILES
    return render json: { error: "Google access expired. Open Drive and try again." }, status: :unprocessable_content if token.blank? || token.bytesize > 4096

    encrypted_token = GoogleDrive::Token.encrypt(token)
    imports = GoogleDriveImport.transaction do
      files.map do |file|
        current_user.google_drive_imports.create!(
          google_file_id: file[:id],
          resource_key: file[:resource_key],
          filename: file[:name].presence || "Google Drive file"
        ).tap { |drive_import| GoogleDriveImportJob.perform_later(drive_import, encrypted_token) }
      end
    end

    render json: { count: imports.size, redirect_url: files_path }, status: :accepted
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  rescue ActionController::ParameterMissing
    render json: { error: "Invalid request." }, status: :bad_request
  end

  private
    def require_authentication
      render json: { error: "Sign in to import files." }, status: :unauthorized unless authenticated?
    end
end
