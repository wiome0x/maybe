module Provider::Auditable
  extend ActiveSupport::Concern

  private

    def with_provider_response(error_transformer: nil, &block)
      started_at = Time.current
      response = super
      elapsed_ms = ((Time.current - started_at) * 1000).round

      log_api_request(
        status: response.success? ? "success" : "error",
        error_message: response.error&.message,
        response_time_ms: elapsed_ms
      )

      response
    end

    def log_api_request(status:, error_message: nil, response_time_ms: nil)
      ApiRequestLog.create!(
        provider_name: provider_name_for_audit,
        endpoint: caller_method_name,
        http_method: "POST",
        request_status: status,
        response_time_ms: response_time_ms,
        error_message: error_message,
        requested_at: Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log API request: #{e.message}")
    end

    def provider_name_for_audit
      self.class.name.demodulize.underscore
    end

    def caller_method_name
      caller_locations(3, 1)&.first&.label || "unknown"
    end
end
