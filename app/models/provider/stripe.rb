class Provider::Stripe
  Error = Class.new(StandardError)
  REDACTED_KEYS = %w[client_secret webhook_secret sig_header authorization].freeze

  def initialize(secret_key:, webhook_secret:)
    @client = Stripe::StripeClient.new(secret_key)
    @webhook_secret = webhook_secret
  end

  def process_event(event_id)
    event = retrieve_event(event_id)

    case event.type
    when /^customer\.subscription\./
      SubscriptionEventProcessor.new(event).process
    else
      Rails.logger.warn "Unhandled event type: #{event.type}"
    end
  end

  def process_webhook_later(webhook_body, sig_header)
    thin_event = client.parse_thin_event(webhook_body, sig_header, webhook_secret)
    StripeEventHandlerJob.perform_later(thin_event.id)
  end

  def create_checkout_session(plan:, family_id:, family_email:, success_url:, cancel_url:)
    customer_payload = {
      email: family_email,
      metadata: {
        family_id: family_id
      }
    }

    customer = audited_call(
      endpoint: "customers.create",
      http_method: "POST",
      request_payload: customer_payload
    ) do
      client.v1.customers.create(customer_payload)
    end

    session_payload = {
      customer: customer.id,
      line_items: [ { price: price_id_for(plan), quantity: 1 } ],
      mode: "subscription",
      allow_promotion_codes: true,
      success_url: success_url,
      cancel_url: cancel_url
    }

    session = audited_call(
      endpoint: "checkout.sessions.create",
      http_method: "POST",
      request_payload: session_payload
    ) do
      client.v1.checkout.sessions.create(session_payload)
    end

    NewCheckoutSession.new(url: session.url, customer_id: customer.id)
  end

  def get_checkout_result(session_id)
    session = audited_call(
      endpoint: "checkout.sessions.retrieve",
      http_method: "GET",
      request_payload: { session_id: session_id }
    ) do
      client.v1.checkout.sessions.retrieve(session_id)
    end

    unless session.status == "complete" && session.payment_status == "paid"
      raise Error, "Checkout session not complete"
    end

    CheckoutSessionResult.new(success?: true, subscription_id: session.subscription)
  rescue StandardError => e
    Sentry.capture_exception(e)
    Rails.logger.error "Error fetching checkout result for session #{session_id}: #{e.message}"
    CheckoutSessionResult.new(success?: false, subscription_id: nil)
  end

  def create_billing_portal_session_url(customer_id:, return_url:)
    payload = {
      customer: customer_id,
      return_url: return_url
    }

    audited_call(
      endpoint: "billing_portal.sessions.create",
      http_method: "POST",
      request_payload: payload
    ) do
      client.v1.billing_portal.sessions.create(payload)
    end.url
  end

  def update_customer_metadata(customer_id:, metadata:)
    payload = {
      customer_id: customer_id,
      metadata: metadata
    }

    audited_call(
      endpoint: "customers.update",
      http_method: "POST",
      request_payload: payload
    ) do
      client.v1.customers.update(customer_id, metadata: metadata)
    end
  end

  private
    attr_reader :client, :webhook_secret

    NewCheckoutSession = Data.define(:url, :customer_id)
    CheckoutSessionResult = Data.define(:success?, :subscription_id)

    def price_id_for(plan)
      prices = {
        monthly: ENV["STRIPE_MONTHLY_PRICE_ID"],
        annual: ENV["STRIPE_ANNUAL_PRICE_ID"]
      }

      prices[plan.to_sym || :monthly]
    end

    def retrieve_event(event_id)
      audited_call(
        endpoint: "events.retrieve",
        http_method: "GET",
        request_payload: { event_id: event_id }
      ) do
        client.v1.events.retrieve(event_id)
      end
    end

    def audited_call(endpoint:, http_method:, request_payload:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      requested_at = Time.current
      response = yield

      create_api_log!(
        provider_name: "stripe",
        endpoint: endpoint,
        http_method: http_method,
        request_status: "success",
        response_code: extract_http_status(response),
        response_time_ms: elapsed_ms(started_at),
        request_payload: redact_sensitive(request_payload),
        response_payload: redact_sensitive(serialize_response(response)),
        error_payload: {},
        requested_at: requested_at
      )

      response
    rescue StandardError => error
      create_api_log!(
        provider_name: "stripe",
        endpoint: endpoint,
        http_method: http_method,
        request_status: "error",
        response_code: extract_http_status(error),
        response_time_ms: elapsed_ms(started_at),
        error_message: error.message,
        request_payload: redact_sensitive(request_payload),
        response_payload: {},
        error_payload: redact_sensitive(serialize_error(error)),
        requested_at: requested_at
      )
      raise
    end

    def create_api_log!(**attributes)
      ApiRequestLog.create!(**attributes)
    rescue StandardError => error
      Rails.logger.error("[Provider::Stripe] Failed to write ApiRequestLog: #{error.class} - #{error.message}")
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def extract_http_status(value)
      if value.respond_to?(:last_response)
        value.last_response&.http_status || value.last_response&.code
      elsif value.respond_to?(:http_status)
        value.http_status
      end
    rescue StandardError
      nil
    end

    def serialize_response(response)
      case response
      when Hash, Array
        response
      else
        response.respond_to?(:to_hash) ? response.to_hash : { "value" => response.to_s }
      end
    end

    def serialize_error(error)
      payload = {
        "class" => error.class.name,
        "message" => error.message
      }
      payload["details"] = error.json_body if error.respond_to?(:json_body) && error.json_body.present?
      payload
    end

    def redact_sensitive(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), sanitized|
          sanitized[key] = REDACTED_KEYS.include?(key.to_s.downcase) ? "[REDACTED]" : redact_sensitive(nested_value)
        end
      when Array
        value.map { |nested_value| redact_sensitive(nested_value) }
      else
        value
      end
    end
end
