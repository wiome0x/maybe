require "binance"

class Provider::Binance < Provider
  # Quote assets used to build symbol pairs (e.g. BTCUSDT, ETHBTC).
  # Stable quotes are excluded when enumerating assets to fetch trades for.
  QUOTE_ASSETS        = %w[USDT USDC BUSD FDUSD BTC ETH BNB EUR TRY BRL AUD RUB GBP USD].freeze
  STABLE_QUOTE_ASSETS = %w[USDT USDC BUSD FDUSD USD].freeze

  # Keys that must never appear in audit logs
  REDACTED_KEYS = %w[signature X-MBX-APIKEY api_key api_secret key secret].freeze

  Error = Class.new(Provider::Error)

  def initialize(api_key:, api_secret:, broker_connection: nil)
    @api_key = api_key
    @api_secret = api_secret
    @broker_connection = broker_connection
  end

  def fetch_account_data
    with_provider_response do
      call(:account)
    end
  end

  # Binance /api/v3/myTrades requires a `symbol` param — it cannot return all trades at once.
  # Accepts an optional `balances` array (from a prior fetch_account_data call) to avoid a
  # redundant /api/v3/account request.
  def fetch_trade_history(since: nil, balances: nil)
    with_provider_response do
      raw_balances = balances || call(:account).fetch("balances", [])

      assets = raw_balances
                 .select { |b| b["free"].to_d + b["locked"].to_d > 0 }
                 .map    { |b| b["asset"].to_s.upcase }
                 .reject { |a| STABLE_QUOTE_ASSETS.include?(a) }

      if assets.empty?
        log_no_op(method_name: "fetch_trade_history", note: "no non-stable assets in account")
        []
      else
        kwargs = {}
        kwargs[:startTime] = (since.to_time.to_i * 1000) if since

        assets.flat_map do |asset|
          QUOTE_ASSETS.filter_map do |quote|
            symbol = "#{asset}#{quote}"
            result = call(:my_trades, symbol: symbol, **kwargs)
            result.empty? ? nil : result
          rescue Binance::ClientError
            # Symbol pair doesn't exist on Binance — expected, skip silently.
            nil
          end
        end.flatten
      end
    end
  end

  def validate_credentials!
    with_provider_response do
      call(:account)
    end
  end

  private
    attr_reader :api_key, :api_secret, :broker_connection

    def audit_broker_connection_id
      broker_connection&.id
    end

    # Calls a Binance::Spot method, logs the result, and returns the parsed data.
    # All SDK calls go through here so every HTTP interaction is audited.
    # Returns string-keyed Hash so callers and the Processor work consistently.
    def call(method, **kwargs)
      started_at = Time.current

      begin
        raw = client.public_send(method, **kwargs)
        elapsed_ms = ((Time.current - started_at) * 1000).round

        # SDK returns symbolized Hash; stringify for consistent storage and Processor access
        data = deep_stringify(raw)

        log_http_request(
          path:             sdk_path(method, kwargs),
          http_method:      "GET",
          response_code:    200,
          status:           "success",
          request_payload:  redact_hash({ method: method, params: kwargs }),
          response_payload: redact_hash(data),
          response_time_ms: elapsed_ms
        )

        data  # return string-keyed form
      rescue Binance::ClientError => e
        elapsed_ms = ((Time.current - started_at) * 1000).round
        body   = e.response&.dig(:body) || {}
        parsed = body.is_a?(String) ? (JSON.parse(body) rescue { "raw" => body }) : body
        code   = parsed["code"] || parsed[:code]
        msg    = build_error_message(e.response&.dig(:status), code, parsed["msg"] || parsed[:msg])

        log_http_request(
          path:             sdk_path(method, kwargs),
          http_method:      "GET",
          response_code:    e.response&.dig(:status),
          status:           "error",
          request_payload:  redact_hash({ method: method, params: kwargs }),
          response_payload: redact_hash(deep_stringify(parsed)),
          error_message:    msg,
          response_time_ms: elapsed_ms
        )

        raise Error.new(msg)
      rescue Binance::ServerError => e
        elapsed_ms = ((Time.current - started_at) * 1000).round
        msg = "Binance server error: #{e.message}"

        log_http_request(
          path:             sdk_path(method, kwargs),
          http_method:      "GET",
          response_code:    500,
          status:           "error",
          request_payload:  redact_hash({ method: method, params: kwargs }),
          response_payload: {},
          error_message:    msg,
          response_time_ms: elapsed_ms
        )

        raise Error.new(msg)
      end
    end

    def client
      @client ||= ::Binance::Spot.new(key: api_key, secret: api_secret, timeout: 10)
    end

    def build_error_message(http_status, binance_code, binance_msg)
      case http_status
      when 401, 403
        "Binance auth error: invalid API key or signature"
      when 418, 429
        "Binance rate limit exceeded: HTTP #{http_status}"
      else
        if %w[-2014 -2015].include?(binance_code.to_s)
          "Binance auth error: #{binance_msg}"
        else
          "Binance API error: HTTP #{http_status} - #{binance_msg}"
        end
      end
    end

    # Maps SDK method name to a human-readable path for audit logs
    def sdk_path(method, kwargs)
      case method
      when :account    then "/api/v3/account"
      when :my_trades  then "/api/v3/myTrades?symbol=#{kwargs[:symbol]}"
      else "/api/v3/#{method}"
      end
    end

    def deep_stringify(value)
      case value
      when Hash  then value.transform_keys(&:to_s).transform_values { |v| deep_stringify(v) }
      when Array then value.map { |v| deep_stringify(v) }
      else value
      end
    end

    def redact_hash(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), acc|
          next if REDACTED_KEYS.include?(key.to_s)
          acc[key] = redact_hash(nested_value)
        end
      when Array then value.map { |v| redact_hash(v) }
      else value
      end
    end
end
