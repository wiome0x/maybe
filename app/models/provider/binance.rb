require "net/http"
require "openssl"

class Provider::Binance < Provider
  BASE_URL = "https://api.binance.com".freeze
  REDACTED_KEYS = %w[signature X-MBX-APIKEY api_key api_secret].freeze

  # Quote assets used to build symbol pairs (e.g. BTCUSDT, ETHBTC)
  QUOTE_ASSETS = %w[USDT USDC BUSD FDUSD BTC ETH BNB EUR TRY BRL AUD RUB GBP USD].freeze
  STABLE_QUOTE_ASSETS = %w[USDT USDC BUSD FDUSD USD].freeze

  Error = Class.new(Provider::Error)

  def initialize(api_key:, api_secret:, broker_connection: nil)
    @api_key = api_key
    @api_secret = api_secret
    @broker_connection = broker_connection
  end

  def fetch_account_data
    with_provider_response do
      get("/api/v3/account", signed: true)
    end
  end

  # Binance /api/v3/myTrades requires a `symbol` param — it cannot return all trades at once.
  # Accepts an optional `balances` array (from a prior fetch_account_data call) to avoid a
  # redundant /api/v3/account request.
  def fetch_trade_history(since: nil, balances: nil)
    with_provider_response do
      raw_balances = balances || get("/api/v3/account", signed: true).fetch("balances", [])

      assets = raw_balances
                 .select { |b| b["free"].to_d + b["locked"].to_d > 0 }
                 .map    { |b| b["asset"].to_s.upcase }
                 .reject { |a| STABLE_QUOTE_ASSETS.include?(a) }

      if assets.empty?
        log_no_op(method_name: "fetch_trade_history", note: "no non-stable assets in account")
        []
      else
        params = {}
        params[:startTime] = (since.to_time.to_i * 1000) if since

        assets.flat_map do |asset|
          QUOTE_ASSETS.filter_map do |quote|
            symbol = "#{asset}#{quote}"
            result = get("/api/v3/myTrades", params: params.merge(symbol: symbol), signed: true)
            result.empty? ? nil : result
          rescue Error
            # Symbol pair doesn't exist on Binance — expected, already logged inside get().
            nil
          end
        end.flatten
      end
    end
  end

  def validate_credentials!
    with_provider_response do
      get("/api/v3/account", signed: true)
    end
  end

  private
    attr_reader :api_key, :api_secret, :broker_connection

    # Override from Provider::Auditable — provides broker_connection_id for audit rows.
    def audit_broker_connection_id
      broker_connection&.id
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

      started_at = Time.current
      response = http.request(request)
      elapsed_ms = ((Time.current - started_at) * 1000).round

      parsed_body = parse_json(response.body)
      redacted_payload = redact_hash(parsed_body)
      redacted_request = { path: path, params: redact_hash(request_params) }

      case response.code.to_i
      when 200
        log_http_request(
          path: path, http_method: "GET",
          response_code: 200, status: "success",
          request_payload: redacted_request,
          response_payload: redacted_payload,
          response_time_ms: elapsed_ms
        )
        parsed_body
      when 401, 403
        msg = "Binance auth error: invalid API key or signature"
        log_http_request(
          path: path, http_method: "GET",
          response_code: response.code.to_i, status: "error",
          request_payload: redacted_request,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: elapsed_ms
        )
        raise Error.new(msg)
      when 418, 429
        msg = "Binance rate limit exceeded: #{response.code}"
        log_http_request(
          path: path, http_method: "GET",
          response_code: response.code.to_i, status: "error",
          request_payload: redacted_request,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: elapsed_ms
        )
        raise Error.new(msg)
      else
        code = parsed_body["code"]
        msg = if %w[-2014 -2015].include?(code.to_s)
          "Binance auth error: #{parsed_body['msg']}"
        else
          "Binance API error: HTTP #{response.code} - #{parsed_body['msg']}"
        end
        log_http_request(
          path: path, http_method: "GET",
          response_code: response.code.to_i, status: "error",
          request_payload: redacted_request,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: elapsed_ms
        )
        raise Error.new(msg)
      end
    end

    def sign(query_string)
      OpenSSL::HMAC.hexdigest("SHA256", api_secret, query_string)
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
