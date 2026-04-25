require "test_helper"
require "ostruct"

# Tests for audit logging behavior (需求 6, 正确性属性 2 & 3)
# Verifies that Provider::Binance and Provider::Schwab correctly write ApiRequestLog
# records via Provider::Auditable#with_provider_response.
class Provider::AuditLogTest < ActiveSupport::TestCase
  SENSITIVE_KEYS = %w[api_key api_secret access_token signature].freeze

  def mock_response(code, body = {})
    OpenStruct.new(code: code.to_s, body: body.to_json)
  end

  # ── Provider::Binance ─────────────────────────────────────────────────────────

  test "Binance: successful call creates exactly one ApiRequestLog record" do
    provider = Provider::Binance.new(api_key: "test_key", api_secret: "test_secret")
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "balances" => [] }))

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Binance: successful call sets request_status to 'success'" do
    provider = Provider::Binance.new(api_key: "test_key", api_secret: "test_secret")
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "balances" => [] }))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "success", log.request_status
    assert_equal 200, log.response_code
    assert_equal "/api/v3/account", log.endpoint
  end

  test "Binance: failed call creates exactly one ApiRequestLog record" do
    provider = Provider::Binance.new(api_key: "bad_key", api_secret: "bad_secret")
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Binance: failed call sets request_status to 'error' and populates error_message" do
    provider = Provider::Binance.new(api_key: "bad_key", api_secret: "bad_secret")
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "error", log.request_status
    assert_not_nil log.error_message
    assert log.error_message.present?
  end

  test "Binance: request_payload does not contain sensitive credential keys" do
    provider = Provider::Binance.new(api_key: "test_key", api_secret: "test_secret")
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "balances" => [] }))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    payload_keys = log.request_payload.keys.map(&:to_s)
    SENSITIVE_KEYS.each do |key|
      assert_not_includes payload_keys, key,
        "request_payload must not contain sensitive key '#{key}'"
    end
  end

  # ── Provider::Schwab ──────────────────────────────────────────────────────────

  test "Schwab: successful call creates exactly one ApiRequestLog record" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "test_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "positions" => [] }))

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Schwab: successful call sets request_status to 'success'" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "test_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "positions" => [] }))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "success", log.request_status
    assert_equal 200, log.response_code
    assert_equal "/accounts/acct-123/positions", log.endpoint
  end

  test "Schwab: failed call creates exactly one ApiRequestLog record" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "expired_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Schwab: failed call sets request_status to 'error' and populates error_message" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "expired_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "error", log.request_status
    assert_not_nil log.error_message
    assert log.error_message.present?
  end

  test "Schwab: request_payload does not contain sensitive credential keys" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "test_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, { "positions" => [] }))

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    payload_keys = log.request_payload.keys.map(&:to_s)
    SENSITIVE_KEYS.each do |key|
      assert_not_includes payload_keys, key,
        "request_payload must not contain sensitive key '#{key}'"
    end
  end
end
