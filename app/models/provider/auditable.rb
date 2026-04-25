module Provider::Auditable
  extend ActiveSupport::Concern

  # Public setter — called by BrokerConnection::Syncer to associate every
  # HTTP audit row with the current Sync record.
  def audit_sync_id=(id)
    @audit_sync_id = id
  end

  private

    # Called by concrete providers after every individual HTTP response.
    # One row per HTTP call — the primary audit trail.
    def log_http_request(path:, http_method:, response_code:, request_payload:, response_payload:,
                         status:, error_message: nil, response_time_ms: nil)
      ApiRequestLog.create!(
        provider_name:        provider_name_for_audit,
        endpoint:             path,
        http_method:          http_method,
        request_status:       status,
        response_code:        response_code,
        response_time_ms:     response_time_ms,
        request_payload:      request_payload,
        response_payload:     status == "success" ? response_payload : {},
        error_payload:        status == "error"   ? response_payload : {},
        error_message:        error_message,
        broker_connection_id: audit_broker_connection_id,
        sync_id:              audit_sync_id,
        requested_at:         Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log API request: #{e.message}")
    end

    # Called when a provider method completes without making any HTTP request
    # (e.g. fetch_trade_history with an empty asset list).  Ensures every
    # with_provider_response invocation has at least one audit row.
    def log_no_op(method_name:, note: nil)
      ApiRequestLog.create!(
        provider_name:        provider_name_for_audit,
        endpoint:             method_name.to_s,
        http_method:          "NONE",
        request_status:       "success",
        response_code:        nil,
        response_time_ms:     0,
        request_payload:      { note: note }.compact,
        response_payload:     {},
        error_payload:        {},
        broker_connection_id: audit_broker_connection_id,
        sync_id:              audit_sync_id,
        requested_at:         Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log no-op audit: #{e.message}")
    end

    def provider_name_for_audit
      self.class.name.demodulize.underscore
    end

    # Override in concrete providers that hold a broker_connection reference.
    def audit_broker_connection_id
      nil
    end

    def audit_sync_id
      @audit_sync_id
    end
end
