class Sends::RevisionsController < ApplicationController
  allow_unverified_access

  def create
    delivery = current_user.sends.find(params[:send_id])
    return redirect_to delivery, alert: "Canceled deliveries cannot be updated." if delivery.canceled?
    return redirect_to delivery, alert: "Collection deliveries update from their collection." if delivery.collection_id?

    attributes = params.expect(revision: [ :attachment_id, :file ])
    return head :bad_request unless attributes[:file].is_a?(String)

    blob = ActiveStorage::Blob.find_signed!(attributes[:file])
    revision = delivery.replace_file!(attributes[:attachment_id], blob)
    current_user.retain_files([ blob ])
    WideEvent.add(delivery_id: delivery.id, revision_number: revision.number, replaced_attachment_id: attributes[:attachment_id])
    redirect_to delivery, notice: "Delivery updated to version #{revision.number}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to delivery, alert: error.record.errors.full_messages.to_sentence
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    head :bad_request
  end
end
