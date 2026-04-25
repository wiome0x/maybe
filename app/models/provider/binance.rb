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
      ApiRequestLog.create!(
        provider_name: provider_name_for_audit,
        endpoint: caller_method_name,
        http_method: "GET",
        request_status: status,
        response_time_ms: response_time_ms,
        request_payload: redacted_payload,
        response_payload: {},
        error_payload: {},
        error_message: error_message,
        requested_at: Time.current
      )
    rescue => e
      Rails.logger.error("Failed to log API request: #{e.message}")
    end

    def redacted_payload
      # Filter out all keys listed in REDACTED_KEYS to prevent credential leakage
      {}
    end

    def get(path, params: {}, signed: false)
      uri = URI("#{BASE_URL}#{path}")

      if signed
        params[:timestamp] = (Time.current.to_f * 1000).to_i
        params[:signature] = sign(URI.encode_www_form(params))
      end

      uri.query = URI.encode_www_form(params) if params.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["X-MBX-APIKEY"] = api_key
      request["Accept"] = "application/json"

      response = http.request(request)
      handle_response!(response)
    end

    def sign(query_string)
      OpenSSL::HMAC.hexdigest("SHA256", api_secret, query_string)
    end

    def handle_response!(response)
      case response.code.to_i
      when 200
        JSON.parse(response.body)
      when 401, 403
        raise Error.new("Binance auth error: invalid API key or signature")
      when 418, 429
        raise Error.new("Binance rate limit exceeded: #{response.code}")
      else
        body = JSON.parse(response.body) rescue {}
        code = body["code"]
        if %w[-2014 -2015].include?(code.to_s)
          raise Error.new("Binance auth error: #{body['msg']}")
        end
        raise Error.new("Binance API error: HTTP #{response.code} - #{body['msg']}")
      end
    end
end
