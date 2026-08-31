class SendsController < ApplicationController
  before_action :set_send, only: %i[show edit update destroy cancel revoke_access rotate_access]
  rate_limit to: 20, within: 1.hour, only: :create, by: -> { current_user.id }

  def index
    @sends = current_user.sends.with_attached_files.includes(:send_events).order(created_at: :desc)
  end

  def new
    @send = current_user.sends.new
    @first_delivery = !current_user.sends.exists?
    if @first_delivery && !session[:first_composer_viewed]
      session[:first_composer_viewed] = true
      WideEvent.add(onboarding_event: "first_composer_viewed")
    end
    set_send_sources
  end

  def create
    return head :bad_request if Array(params.dig(:send, :files)).any? { |file| !file.is_a?(String) }

    @first_delivery = !current_user.sends.exists?
    attributes = send_params
    collection_id = attributes.delete(:collection_id)
    @send = current_user.sends.new(attributes)
    if collection_id.present?
      return head :bad_request if Array(attributes[:files]).compact_blank.any?

      @collection = current_user.collections.active.find(collection_id)
      @send.collection = @collection
    end
    if schedule_conversion_missing?
      @send.errors.add(:scheduled_at, "could not be converted to UTC. Refresh and try again")
      set_send_sources
      return render :new, status: :unprocessable_entity
    end

    if @send.deliver!
      blobs = @send.files.blobs.to_a
      onboarding_duration_ms = ((Time.current.to_i - session.delete(:send_intent_started_at).to_i) * 1000 if @first_delivery && session[:send_intent_started_at])
      WideEvent.add(delivery_id: @send.id, delivery_operation: @send.scheduled? ? "scheduled" : "created", scheduled_at: @send.scheduled_at&.iso8601(3), file_count: blobs.size, send_bytes: blobs.sum(&:byte_size), first_delivery: @first_delivery, onboarding_event: ("first_delivery_completed" if @first_delivery), onboarding_duration_ms:)
      notice = @send.scheduled? ? "Delivery scheduled." : "We’re emailing the delivery link to #{@send.recipient_email}."
      session[:first_delivery_completed_id] = @send.id if @first_delivery
      redirect_to send_path(@send, onboarding: ("complete" if @first_delivery)), notice: (notice unless @first_delivery)
    else
      WideEvent.add(first_delivery: true, onboarding_event: "first_delivery_failed") if @first_delivery
      set_send_sources
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @revisions = @send.delivery_revisions.includes(files_attachments: :blob).order(number: :desc)
    # Scoped through the delivery, which set_send already scoped to the caller,
    # so another user's history is not found rather than forbidden.
    @audit_events = AuditEvent.for_target(@send).newest_first
    @first_delivery_complete = params[:onboarding] == "complete" && session.delete(:first_delivery_completed_id).to_i == @send.id
  end

  def edit
    redirect_to @send, alert: "Published and canceled deliveries cannot be edited." unless @send.publication_pending?
  end

  def update
    if schedule_conversion_missing?
      @send.errors.add(:scheduled_at, "could not be converted to UTC. Refresh and try again")
      return render :edit, status: :unprocessable_entity
    end

    if @send.update_before_publication(update_send_params)
      DeliveryEmailJob.enqueue(@send)
      WideEvent.add(delivery_id: @send.id, delivery_operation: "rescheduled", scheduled_at: @send.scheduled_at&.iso8601(3))
      redirect_to @send, notice: @send.scheduled? ? "Delivery schedule updated." : "Delivery is being published now."
    elsif @send.publication_pending?
      render :edit, status: :unprocessable_entity
    else
      redirect_to @send, alert: "Published and canceled deliveries cannot be edited."
    end
  end

  def destroy
    if @send.published? && @send.slug.present?
      WideEvent.add(delivery_id: @send.id, delivery_operation: "delete_rejected")
      return redirect_to @send, alert: "A published delivery link cannot be deleted. Revoke access instead."
    end

    unless @send.published?
      WideEvent.add(delivery_id: @send.id, delivery_operation: "delete_rejected", scheduled_at: @send.scheduled_at&.iso8601(3))
      # ponytail: retain unpublished rows so stale delayed jobs can no-op against database state.
      return redirect_to @send, alert: "Unpublished deliveries cannot be deleted."
    end

    @send.destroy!
    redirect_to sends_path, notice: "Delivery deleted. Files kept in My Files are unchanged."
  end

  def cancel
    if @send.cancel!
      WideEvent.add(delivery_id: @send.id, delivery_operation: "canceled", scheduled_at: @send.scheduled_at&.iso8601(3), canceled_at: @send.canceled_at.iso8601(3))
      redirect_to @send, notice: "Scheduled delivery canceled."
    else
      redirect_to @send, alert: "Published and canceled deliveries cannot be canceled."
    end
  end

  def revoke_access
    return redirect_to @send, alert: "This delivery has not been published." unless @send.published?

    @send.revoke_access!
    redirect_to @send, notice: "Recipient access revoked."
  end

  def rotate_access
    @send.update!(email_status: "pending")
    AuditEvent.record!(action: "delivery.access_rotation_requested", target: @send)
    @send.published? ? DeliveryAccessEmailJob.perform_later(@send) : DeliveryEmailJob.enqueue(@send)
    redirect_to @send, notice: "We’re emailing a new delivery link to #{@send.recipient_email}."
  end

  private
    def set_send
      @send = current_user.sends.with_attached_files.includes(:send_events).find(params[:id])
    end

    def send_params
      params.expect(send: [ :recipient_email, :message, :scheduled_at, :slug, :collection_id, files: [] ])
    end

    def update_send_params
      params.expect(send: [ :recipient_email, :message, :scheduled_at, :slug ])
    end

    def schedule_conversion_missing?
      params.dig(:send, :scheduled_local).present? && params.dig(:send, :schedule_synced) != "1"
    end

    def set_send_sources
      @collections = current_user.collections.active.joins(:collection_files).distinct.includes(:blobs).order(:name)
      @collection ||= @collections.find { |collection| collection.id.to_s == (params[:collection_id] || params.dig(:send, :collection_id)).to_s }
      files = current_user.files.attachments.includes(:blob).order(created_at: :desc)
      selected_file = files.find_by(id: params[:file_id])
      @library_files = [ selected_file, *files.where.not(id: selected_file&.id).limit(11) ].compact
      @selected_file_id = selected_file&.id
    end
end
