class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_authentication

  def plaid
    process_plaid_webhook(region: :us, endpoint: "webhooks/plaid")
  rescue => error
    log_plaid_webhook_error(region: :us, endpoint: "webhooks/plaid", error: error)
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def plaid_eu
    process_plaid_webhook(region: :eu, endpoint: "webhooks/plaid_eu")
  rescue => error
    log_plaid_webhook_error(region: :eu, endpoint: "webhooks/plaid_eu", error: error)
    Sentry.capture_exception(error)
    render json: { error: "Invalid webhook: #{error.message}" }, status: :bad_request
  end

  def stripe
    stripe_provider = Provider::Registry.get_provider(:stripe)

    begin
      webhook_body = request.body.read
      sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

      stripe_provider.process_webhook_later(webhook_body, sig_header)

      head :ok
    rescue JSON::ParserError => error
      Sentry.capture_exception(error)
      Rails.logger.error "JSON parser error: #{error.message}"
      head :bad_request
    rescue Stripe::SignatureVerificationError => error
      Sentry.capture_exception(error)
      Rails.logger.error "Stripe signature verification error: #{error.message}"
      head :bad_request
    end
  end

  private
    def process_plaid_webhook(region:, endpoint:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      webhook_body = request.body.read
      plaid_verification_header = request.headers["Plaid-Verification"]
      @last_plaid_webhook_body = webhook_body
      @last_plaid_verification_header = plaid_verification_header
      parsed_body = parse_json_or_raw(webhook_body)

      client = Provider::Registry.plaid_provider_for_region(region)

      client.validate_webhook!(plaid_verification_header, webhook_body)

      PlaidItem::WebhookProcessor.new(webhook_body).process

      create_plaid_webhook_log!(
        region: region,
        endpoint: endpoint,
        success: true,
        duration_ms: elapsed_ms(started_at),
        request_payload: {
          headers: { "Plaid-Verification" => "[REDACTED]" },
          body: parsed_body
        },
        response_payload: { received: true }
      )

      render json: { received: true }, status: :ok
    end

    def log_plaid_webhook_error(region:, endpoint:, error:)
      create_plaid_webhook_log!(
        region: region,
        endpoint: endpoint,
        success: false,
        request_payload: {
          headers: { "Plaid-Verification" => @last_plaid_verification_header.present? ? "[REDACTED]" : nil }.compact,
          body: parse_json_or_raw(@last_plaid_webhook_body)
        },
        error_payload: {
          class: error.class.name,
          message: error.message
        }
      )
    end

    def create_plaid_webhook_log!(region:, endpoint:, success:, request_payload:, response_payload: {}, error_payload: {}, duration_ms: nil)
      body = request_payload[:body] || {}
      plaid_item = PlaidItem.find_by(plaid_id: body["item_id"])

      PlaidApiLog.create!(
        plaid_item_id: plaid_item&.id,
        region: region.to_s,
        source: "webhook",
        endpoint: endpoint,
        success: success,
        duration_ms: duration_ms,
        webhook_type: body["webhook_type"],
        webhook_code: body["webhook_code"],
        request_payload: request_payload,
        response_payload: response_payload,
        error_payload: error_payload,
        requested_at: Time.current
      )
    rescue => e
      Rails.logger.error("[WebhooksController] Failed to write Plaid webhook log: #{e.class} - #{e.message}")
    end

    def parse_json_or_raw(value)
      return {} if value.blank?

      JSON.parse(value)
    rescue JSON::ParserError
      { "_raw" => value.to_s }
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end
end
