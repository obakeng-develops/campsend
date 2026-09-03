class Api::V1::DeliveriesController < ApplicationController
  include ApiTokenAuthentication

  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  allow_unauthenticated_access
  skip_forgery_protection
  before_action :require_api_token
  before_action :require_writable_api_token, only: :create
  rate_limit to: 120, within: 1.hour, by: -> { @api_token.id }

  rescue_from ActiveRecord::RecordNotFound do
    render_api_error("No delivery with that identifier.", :not_found)
  end

  def index
    deliveries = current_user.sends.with_attached_files.includes(:send_events).order(created_at: :desc).to_a
    # display_status is derived rather than stored, so filtering happens here.
    deliveries = deliveries.select { |delivery| delivery.display_status == params[:status] } if params[:status].present?

    render json: { deliveries: deliveries.first(limit).map { |delivery| Agent::DeliveryPresenter.summary(delivery) } }
  end

  def show
    render json: Agent::DeliveryPresenter.detail(find_delivery)
  end

  def create
    # Caught here because the model reports it as a revision error, twice, in
    # words about its own internals.
    return render_api_error("Give at least one file id in file_ids.", :unprocessable_content) if file_ids.empty?

    blobs = owned_blobs
    return render_api_error("Some of those files are not yours, or do not exist.", :unprocessable_content) unless blobs.size == file_ids.size

    delivery = current_user.sends.new(**delivery_params, files: blobs)
    return render_api_error(delivery.errors.full_messages.to_sentence, :unprocessable_content) unless delivery.deliver!

    WideEvent.add(delivery_id: delivery.id, delivery_operation: delivery.scheduled? ? "scheduled" : "created", file_count: blobs.size)
    render json: Agent::DeliveryPresenter.detail(delivery.reload), status: :created
  end

  private
    # Scoped to the caller first, so another user's delivery is not found rather
    # than forbidden.
    def find_delivery
      scope = current_user.sends.with_attached_files.includes(:send_events)
      scope.find_by(slug: params[:id]) || scope.find_by!(public_id: params[:id])
    end

    def delivery_params
      {
        recipient_email: params[:recipient_email],
        message: params[:message],
        slug: params[:slug],
        scheduled_at: parse_time(params[:scheduled_at])
      }.compact
    end

    def file_ids
      Array(params[:file_ids]).map { |id| Integer(id, exception: false) }.compact.uniq
    end

    def owned_blobs
      return [] if file_ids.empty?

      current_user.uploaded_blobs.where(id: file_ids).to_a
    end

    def limit
      params[:limit].present? ? params[:limit].to_i.clamp(1, MAX_LIMIT) : DEFAULT_LIMIT
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      # Left nil so the model reports it rather than raising here.
      nil
    end
end
