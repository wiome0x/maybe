require "net/http"
require "openssl"

class Provider::Binance < Provider
  BASE_URL = "https://api.binance.com".freeze
  REDACTED_KEYS = %w[signature X-MBX-APIKEY api_key api_secret].freeze

  Error = Class.new(Provider::Error)

  def initialize(api_key:, api_secret:)
    @api_key = api_key
    @api_secret = api_secret
  end

  def fetch_account_data
    with_provider_response do
      get("/api/v3/account", signed: true)
    end
  end

  def fetch_trade_history(symbol: nil, since: nil)
    with_provider_response do
      params = {}
      params[:startTime] = (since.to_time.to_i * 1000) if since
      get("/api/v3/myTrades", params: params, signed: true)
    end
  end

  def validate_credentials!
    with_provider_response do
      get("/api/v3/account", signed: true)
    end
  end

  private
    attr_reader :api_key, :api_secret

    def log_api_request(status:, error_message: nil, response_time_ms: nil)
      audit_context = @last_audit_context || {}

      ApiRequestLog.create!(
        provider_name: provider_name_for_audit,
        endpoint: audit_context[:path] || caller_method_name,
        http_method: audit_context[:http_method] || "GET",
        request_status: status,
        response_code: audit_context[:response_code],
        response_time_ms: response_time_ms,
        request_payload: audit_context[:request_payload] || {},
        response_payload: status == "success" ? (audit_context[:response_payload] || {}) : {},
        error_payload: status == "error" ? (audit_context[:response_payload] || {}) : {},
        error_message: error_message,
        requested_at: Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log API request: #{e.message}")
    ensure
      @last_audit_context = nil
    end

    def get(path, params: {}, signed: false)
      uri = URI("#{BASE_URL}#{path}")
      request_params = params.deep_dup

      if signed
        request_params[:timestamp] = (Time.current.to_f * 1000).to_i
        request_params[:signature] = sign(URI.encode_www_form(request_params))
      end

      uri.query = URI.encode_www_form(request_params) if request_params.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["X-MBX-APIKEY"] = api_key
      request["Accept"] = "application/json"

      response = http.request(request)
      handle_response!(
        response,
        path: path,
        http_method: "GET",
        request_payload: {
          path: path,
          params: redact_hash(request_params)
        }
      )
    end

    def sign(query_string)
      OpenSSL::HMAC.hexdigest("SHA256", api_secret, query_string)
    end

    def handle_response!(response, path:, http_method:, request_payload:)
      parsed_body = parse_json(response.body)
      @last_audit_context = {
        path: path,
        http_method: http_method,
        response_code: response.code.to_i,
        request_payload: request_payload,
        response_payload: redact_hash(parsed_body)
      }

      case response.code.to_i
      when 200
        parsed_body
      when 401, 403
        raise Error.new("Binance auth error: invalid API key or signature")
      when 418, 429
        raise Error.new("Binance rate limit exceeded: #{response.code}")
      else
        code = parsed_body["code"]
        if %w[-2014 -2015].include?(code.to_s)
          raise Error.new("Binance auth error: #{parsed_body['msg']}")
        end
        raise Error.new("Binance API error: HTTP #{response.code} - #{parsed_body['msg']}")
      end
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError
      { "raw_body" => body.to_s }
    end

    def redact_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), acc|
          next if REDACTED_KEYS.include?(key.to_s)

          acc[key] = redact_hash(nested_value)
        end
      when Array
        value.map { |item| redact_hash(item) }
      else
        value
      end
    end
end
