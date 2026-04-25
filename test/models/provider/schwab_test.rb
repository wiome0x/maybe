require "test_helper"
require "ostruct"

class Provider::SchwabTest < ActiveSupport::TestCase
  setup do
    @broker_connection = OpenStruct.new(broker_account_id: "test-account-123")
    @provider = Provider::Schwab.new(
      access_token: "test_access_token",
      broker_connection: @broker_connection
    )
  end

  def mock_response(code, body)
    OpenStruct.new(code: code.to_s, body: body.to_json)
  end

  # ── Success path ──────────────────────────────────────────────────────────────

  test "fetch_account_data returns provider response with account data on success" do
    positions_payload = { "positions" => [ { "symbol" => "AAPL", "quantity" => 10 } ] }
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(200, positions_payload))

    result = @provider.fetch_account_data

    assert result.success?
    assert_equal positions_payload, result.data
  end

  # ── 401 token expired ─────────────────────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'token expired' on 401 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(401, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "token expired"
  end

  # ── 403 requires reauth ───────────────────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'requires_reauth' on 403 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(403, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "requires_reauth"
  end

  # ── 5xx server errors ─────────────────────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with HTTP status code on 500 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(500, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "500"
  end

  test "fetch_account_data raises Provider::Error with HTTP status code on 503 response" do
    Net::HTTP.any_instance.stubs(:request).returns(mock_response(503, {}))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "503"
  end
end
