require "binance"

class Provider::Binance < Provider
  # Quote assets used to build symbol pairs (e.g. BTCUSDT, ETHBTC).
  QUOTE_ASSETS        = %w[USDT USDC BUSD FDUSD BTC ETH BNB EUR TRY BRL AUD RUB GBP USD].freeze
  STABLE_QUOTE_ASSETS = %w[USDT USDC BUSD FDUSD USD].freeze

  # Probed when the account holds only stable coins (all positions sold).
  # Covers the most actively traded spot pairs on Binance.
  FALLBACK_PROBE_ASSETS = %w[
    BTC ETH BNB SOL XRP ADA DOGE DOT AVAX MATIC LINK UNI ATOM LTC BCH
    ETC FIL NEAR APT ARB OP SUI PEPE SHIB TRX TON
  ].freeze

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
  #
  # Strategy:
  #   1. Collect candidate base assets from current balances + prior trade history.
  #   2. If none found (account holds only stable coins), fall back to FALLBACK_PROBE_ASSETS.
  #   3. Phase 1 — USDT probe: find which candidates actually have any trades (avoids N×14 requests).
  #   4. Phase 2 — full quote sweep: for confirmed assets, collect trades across all quote pairs.
  def fetch_trade_history(since: nil, balances: nil)
    with_provider_response do
      raw_balances = balances || call(:account).fetch("balances", [])

      # Assets currently held (excluding stable coins)
      held_assets = raw_balances
                      .map    { |b| b["asset"].to_s.upcase }
                      .reject { |a| STABLE_QUOTE_ASSETS.include?(a) || a.blank? }

      # Assets seen in previously stored trade history (incremental syncs)
      prior_assets = Array(broker_connection&.raw_transactions_payload)
                       .filter_map { |t| extract_base_asset(t["symbol"].to_s.upcase) }
                       .reject     { |a| STABLE_QUOTE_ASSETS.include?(a) }

      candidates = (held_assets + prior_assets).uniq

      # Fallback: account holds only stable coins (e.g. all positions sold to USDT).
      # Probe common assets so we don't miss closed-position trade history.
      candidates = FALLBACK_PROBE_ASSETS if candidates.empty?

      kwargs = {}
      kwargs[:startTime] = (since.to_time.to_i * 1000) if since

      # Phase 1 — USDT probe: find which assets actually have trades.
      traded_assets = candidates.select do |asset|
        begin
          call(:my_trades, symbol: "#{asset}USDT", **kwargs).any?
        rescue Binance::ClientError
          false
        end
      end

      if traded_assets.empty?
        log_no_op(method_name: "fetch_trade_history", note: "no trades found for any candidate asset")
        next []
      end

      # Phase 2 — full quote sweep: collect trades across all quote pairs for confirmed assets.
      traded_assets.flat_map do |asset|
        QUOTE_ASSETS.flat_map do |quote|
          begin
            call(:my_trades, symbol: "#{asset}#{quote}", **kwargs)
          rescue Binance::ClientError
            []
          end
        end
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

    # Calls a Binance::Spot method, logs the result, and returns string-keyed data.
    # Every HTTP interaction is audited here — success and failure both write to ApiRequestLog.
    def call(method, **kwargs)
      started_at = Time.current

      begin
        raw = client.public_send(method, **kwargs)
        elapsed_ms = ((Time.current - started_at) * 1000).round
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

        data
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
      when 401, 403 then "Binance auth error: invalid API key or signature"
      when 418, 429 then "Binance rate limit exceeded: HTTP #{http_status}"
      else
        if %w[-2014 -2015].include?(binance_code.to_s)
          "Binance auth error: #{binance_msg}"
        else
          "Binance API error: HTTP #{http_status} - #{binance_msg}"
        end
      end
    end

    def sdk_path(method, kwargs)
      case method
      when :account   then "/api/v3/account"
      when :my_trades then "/api/v3/myTrades?symbol=#{kwargs[:symbol]}"
      else "/api/v3/#{method}"
      end
    end

    # Strips the quote asset suffix to get the base asset.
    # e.g. "BTCUSDT" -> "BTC", "ETHBTC" -> "ETH"
    def extract_base_asset(symbol)
      quote = QUOTE_ASSETS.find { |q| symbol.end_with?(q) }
      return nil unless quote

      base = symbol.delete_suffix(quote)
      base.present? ? base : nil
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
