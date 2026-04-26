require "test_helper"

# Tests for audit logging behavior (需求 6, 正确性属性 2 & 3)
# Verifies that Provider::Binance correctly writes ApiRequestLog records.
class Provider::AuditLogTest < ActiveSupport::TestCase
  SENSITIVE_KEYS = %w[api_key api_secret access_token signature].freeze

  def binance_provider
    Provider::Binance.new(api_key: "test_key", api_secret: "test_secret")
  end

  def stub_binance_success(provider)
    client = mock
    provider.stubs(:client).returns(client)
    client.stubs(:account).returns({ "balances" => [] })
  end

  def stub_binance_failure(provider)
    client = mock
    provider.stubs(:client).returns(client)
    err = ::Binance::ClientError.new
    err.stubs(:response).returns({ status: 401, body: {}.to_json })
    client.stubs(:account).raises(err)
  end

  # ── Provider::Binance ─────────────────────────────────────────────────────────

  test "Binance: successful call creates exactly one ApiRequestLog record" do
    provider = binance_provider
    stub_binance_success(provider)

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Binance: successful call sets request_status to 'success'" do
    provider = binance_provider
    stub_binance_success(provider)

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "success", log.request_status
    assert_equal 200, log.response_code
    assert_equal "/api/v3/account", log.endpoint
  end

  test "Binance: failed call creates exactly one ApiRequestLog record" do
    provider = binance_provider
    stub_binance_failure(provider)

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Binance: failed call sets request_status to 'error' and populates error_message" do
    provider = binance_provider
    stub_binance_failure(provider)

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "error", log.request_status
    assert log.error_message.present?
  end

  test "Binance: request_payload does not contain sensitive credential keys" do
    provider = binance_provider
    stub_binance_success(provider)

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
    Net::HTTP.any_instance.stubs(:request).returns(
      OpenStruct.new(code: "200", body: { "positions" => [] }.to_json)
    )

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Schwab: successful call sets request_status to 'success'" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "test_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(
      OpenStruct.new(code: "200", body: { "positions" => [] }.to_json)
    )

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "success", log.request_status
    assert_equal 200, log.response_code
    assert_equal "/accounts/acct-123/positions", log.endpoint
  end

  test "Schwab: failed call creates exactly one ApiRequestLog record" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "expired_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(
      OpenStruct.new(code: "401", body: {}.to_json)
    )

    assert_difference "ApiRequestLog.count", 1 do
      provider.fetch_account_data
    end
  end

  test "Schwab: failed call sets request_status to 'error' and populates error_message" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "expired_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(
      OpenStruct.new(code: "401", body: {}.to_json)
    )

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    assert_equal "error", log.request_status
    assert log.error_message.present?
  end

  test "Schwab: request_payload does not contain sensitive credential keys" do
    broker_connection = OpenStruct.new(broker_account_id: "acct-123")
    provider = Provider::Schwab.new(access_token: "test_token", broker_connection: broker_connection)
    Net::HTTP.any_instance.stubs(:request).returns(
      OpenStruct.new(code: "200", body: { "positions" => [] }.to_json)
    )

    provider.fetch_account_data

    log = ApiRequestLog.order(created_at: :desc).first
    payload_keys = log.request_payload.keys.map(&:to_s)
    SENSITIVE_KEYS.each do |key|
      assert_not_includes payload_keys, key,
        "request_payload must not contain sensitive key '#{key}'"
    end
  end
end
