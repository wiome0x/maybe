require "test_helper"
require "ostruct"

class Provider::BinanceTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Binance.new(api_key: "test_api_key", api_secret: "test_api_secret")
  end

  # Helper to build a mock HTTP response
  def mock_response(code, body)
    OpenStruct.new(code: code.to_s, body: body.to_json)
  end

  # ── Success path ──────────────────────────────────────────────────────────────

  test "fetch_account_data returns provider response with account data on success" do
    account_payload = { "balances" => [ { "asset" => "BTC", "free" => "0.5" } ] }
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, account_payload))

    result = @provider.fetch_account_data

    assert result.success?
    assert_equal account_payload, result.data
  end

  # ── HMAC-SHA256 signature ─────────────────────────────────────────────────────

  test "fetch_account_data includes a signature query parameter in the request" do
    account_payload = { "balances" => [] }
    captured_request = nil

    Net::HTTP.any_instance.stubs(:request).with { |req| captured_request = req; true }
                                          .returns(mock_response(200, account_payload))

    @provider.fetch_account_data

    assert_not_nil captured_request, "Expected an HTTP request to be made"
    query = URI.decode_www_form(URI.parse(captured_request.path).query || "").to_h
    assert query.key?("signature"), "Expected 'signature' param in request query string"
    assert_match(/\A[0-9a-f]{64}\z/, query["signature"], "Signature should be a 64-char hex string (HMAC-SHA256)")
  end

  # ── Auth errors (HTTP 401 / 403) ──────────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'auth error' on 401 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  test "fetch_account_data raises Provider::Error with 'auth error' on 403 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(403, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  # ── Rate limit errors (HTTP 429 / 418) ───────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'rate limit' on 429 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(429, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "rate limit"
  end

  test "fetch_account_data raises Provider::Error with 'rate limit' on 418 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(418, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "rate limit"
  end

  # ── Binance error codes -2014 / -2015 ────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'auth error' on -2014 error code" do
    body = { "code" => -2014, "msg" => "API-key format invalid." }
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(400, body))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  test "fetch_account_data raises Provider::Error with 'auth error' on -2015 error code" do
    body = { "code" => -2015, "msg" => "Invalid API-key, IP, or permissions for action." }
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(400, body))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end
end
