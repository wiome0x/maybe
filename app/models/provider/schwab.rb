require "net/http"
require "base64"

class Provider::Schwab < Provider
  BASE_URL  = "https://api.schwabapi.com/trader/v1".freeze
  TOKEN_URL = "https://api.schwabapi.com/v1/oauth/token".freeze
  AUTH_URL  = "https://api.schwabapi.com/v1/oauth/authorize".freeze

  Error = Class.new(Provider::Error)

  REDACTED_KEYS = %w[access_token refresh_token authorization token].freeze

  def initialize(access_token:, refresh_token: nil, broker_connection: nil)
    @access_token = access_token
    @refresh_token = refresh_token
    @broker_connection = broker_connection
  end

  def fetch_account_data
    with_provider_response do
      get("/accounts/#{broker_account_id}/positions")
    end
  end

  def fetch_transaction_history(since: nil)
    with_provider_response do
      params = {}
      params[:startDate] = since.iso8601 if since
      get("/accounts/#{broker_account_id}/transactions", params: params)
    end
  end

  def revoke_token!
    with_provider_response do
      post(TOKEN_URL, body: { token: access_token, token_type_hint: "access_token" })
    end
  end

  def self.authorization_url(state:)
    params = {
      client_id: ENV["SCHWAB_CLIENT_ID"],
      redirect_uri: ENV["SCHWAB_REDIRECT_URI"],
      response_type: "code",
      scope: "readonly",
      state: state
    }
    "#{AUTH_URL}?#{URI.encode_www_form(params)}"
  end

  private_class_method def self.extract_account_id_from_token(id_token)
    return nil if id_token.blank?

    # JWT is three Base64url-encoded segments separated by dots
    payload_segment = id_token.split(".")[1]
    return nil if payload_segment.blank?

    # Base64url decode (pad to multiple of 4)
    padded = payload_segment + "=" * ((4 - payload_segment.length % 4) % 4)
    claims = JSON.parse(Base64.urlsafe_decode64(padded))
    claims["sub"]
  rescue
    nil
  end

  def self.exchange_code(code:)
    # Schwab requires Basic auth: Base64(client_id:client_secret)
    credentials = Base64.strict_encode64("#{ENV['SCHWAB_CLIENT_ID']}:#{ENV['SCHWAB_CLIENT_SECRET']}")

    uri = URI(TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{credentials}"
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = URI.encode_www_form(
      grant_type: "authorization_code",
      code: code,
      redirect_uri: ENV["SCHWAB_REDIRECT_URI"]
    )

    response = http.request(request)
    body = JSON.parse(response.body)

    raise Error.new("Schwab token exchange failed: HTTP #{response.code} — #{body['error_description'] || body['error']}") unless response.code.to_i == 200

    # Decode the id_token JWT to extract the account number hash (sub claim)
    broker_account_id = extract_account_id_from_token(body["id_token"])

    {
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      expires_in: body["expires_in"].to_i,
      broker_account_id: broker_account_id
    }
  end

  def self.refresh_token(refresh_token:)
    credentials = Base64.strict_encode64("#{ENV['SCHWAB_CLIENT_ID']}:#{ENV['SCHWAB_CLIENT_SECRET']}")

    uri = URI(TOKEN_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 10
    http.read_timeout = 15

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Basic #{credentials}"
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = URI.encode_www_form(
      grant_type: "refresh_token",
      refresh_token: refresh_token
    )

    response = http.request(request)
    body = JSON.parse(response.body)

    raise Error.new("Schwab token refresh failed: HTTP #{response.code} — #{body['error_description'] || body['error']}") unless response.code.to_i == 200

    {
      access_token: body["access_token"],
      refresh_token: body["refresh_token"],
      expires_in: body["expires_in"].to_i
    }
  end

  private
    attr_reader :access_token, :refresh_token, :broker_connection

    # Override from Provider::Auditable — provides broker_connection_id for audit rows.
    def audit_broker_connection_id
      broker_connection&.id
    end

    def broker_account_id
      broker_connection&.broker_account_id
    end

    def get(path, params: {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params) if params.any?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Accept"] = "application/json"

      started_at = Time.current
      response = http.request(request)
      elapsed_ms = ((Time.current - started_at) * 1000).round

      handle_response!(
        response,
        path: path, http_method: "GET",
        request_payload: { path: path, params: redact_hash(params), broker_account_id: broker_account_id },
        response_time_ms: elapsed_ms
      )
    end

    def post(url, body: {})
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{access_token}"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Accept"] = "application/json"
      request.body = URI.encode_www_form(body)

      started_at = Time.current
      response = http.request(request)
      elapsed_ms = ((Time.current - started_at) * 1000).round

      handle_response!(
        response,
        path: uri.path, http_method: "POST",
        request_payload: { path: uri.path, body: redact_hash(body), broker_account_id: broker_account_id },
        response_time_ms: elapsed_ms
      )
    end

    def handle_response!(response, path:, http_method:, request_payload:, response_time_ms: nil)
      parsed_body = parse_json(response.body)
      redacted_payload = redact_hash(parsed_body)
      code = response.code.to_i

      case code
      when 200
        log_http_request(
          path: path, http_method: http_method,
          response_code: code, status: "success",
          request_payload: request_payload,
          response_payload: redacted_payload,
          response_time_ms: response_time_ms
        )
        parsed_body
      when 401
        msg = "Schwab token expired: requires refresh"
        log_http_request(
          path: path, http_method: http_method,
          response_code: code, status: "error",
          request_payload: request_payload,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: response_time_ms
        )
        raise Error.new(msg)
      when 403
        msg = "Schwab auth error: requires_reauth"
        log_http_request(
          path: path, http_method: http_method,
          response_code: code, status: "error",
          request_payload: request_payload,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: response_time_ms
        )
        raise Error.new(msg)
      when 500..599
        msg = "Schwab server error: HTTP #{code}"
        log_http_request(
          path: path, http_method: http_method,
          response_code: code, status: "error",
          request_payload: request_payload,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: response_time_ms
        )
        raise Error.new(msg)
      else
        msg = "Schwab API error: HTTP #{code}"
        log_http_request(
          path: path, http_method: http_method,
          response_code: code, status: "error",
          request_payload: request_payload,
          response_payload: redacted_payload,
          error_message: msg, response_time_ms: response_time_ms
        )
        raise Error.new(msg)
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
          next if REDACTED_KEYS.any? { |k| key.to_s.match?(/#{k}/i) }
          acc[key] = redact_hash(nested_value)
        end
      when Array
        value.map { |item| redact_hash(item) }
      else
        value
      end
    end
end
