class Sends::FilesController < ApplicationController
  allow_unverified_access
  include ServeBlob

  def show
    send_record = current_user.sends.find(params[:send_id])
    attachment = ActiveStorage::Attachment.where(record: send_record.delivery_revisions, name: "files").find(params[:id])
    disposition = ActiveStorage.web_image_content_types.include?(attachment.blob.content_type) ? "inline" : "attachment"

    serve_blob attachment.blob, disposition: disposition
  end
end
