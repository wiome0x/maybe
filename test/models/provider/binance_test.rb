require "test_helper"
require "ostruct"

class Provider::BinanceTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Binance.new(api_key: "test_api_key", api_secret: "test_api_secret")
  end

  # Helper: build a fake Binance::ClientError with the given HTTP status and body hash.
  def binance_client_error(status, body = {})
    err = ::Binance::ClientError.new
    err.stubs(:response).returns({ status: status, body: body.to_json })
    err
  end

  # ── Success path ──────────────────────────────────────────────────────────────

  test "fetch_account_data returns provider response with account data on success" do
    account_payload = { "balances" => [ { "asset" => "BTC", "free" => "0.5" } ] }
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).returns(account_payload)

    result = @provider.fetch_account_data

    assert result.success?
    assert_equal account_payload, result.data
  end

  # ── HMAC-SHA256 signature ─────────────────────────────────────────────────────

  test "fetch_account_data includes a signature query parameter in the request" do
    # This test verifies the real Binance::Spot SDK signs requests correctly.
    # We intercept at the Net::HTTP level so the signature is visible in the URL.
    account_payload = { "balances" => [] }
    captured_request = nil

    Net::HTTP.any_instance.stubs(:request).with { |req| captured_request = req; true }
                                          .returns(OpenStruct.new(code: "200", body: account_payload.to_json))

    @provider.fetch_account_data

    assert_not_nil captured_request, "Expected an HTTP request to be made"
    query = URI.decode_www_form(URI.parse(captured_request.path).query || "").to_h
    assert query.key?("signature"), "Expected 'signature' param in request query string"
    assert_match(/\A[0-9a-f]{64}\z/, query["signature"], "Signature should be a 64-char hex string (HMAC-SHA256)")
  end

  # ── Auth errors (HTTP 401 / 403) ──────────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'auth error' on 401 response" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(401))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  test "fetch_account_data raises Provider::Error with 'auth error' on 403 response" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(403))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  # ── Rate limit errors (HTTP 429 / 418) ───────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'rate limit' on 429 response" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(429))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "rate limit"
  end

  test "fetch_account_data raises Provider::Error with 'rate limit' on 418 response" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(418))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "rate limit"
  end

  # ── Binance error codes -2014 / -2015 ────────────────────────────────────────

  test "fetch_account_data raises Provider::Error with 'auth error' on -2014 error code" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(400, { "code" => -2014, "msg" => "API-key format invalid." }))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  test "fetch_account_data raises Provider::Error with 'auth error' on -2015 error code" do
    client = mock
    @provider.stubs(:client).returns(client)
    client.stubs(:account).raises(binance_client_error(400, { "code" => -2015, "msg" => "Invalid API-key, IP, or permissions for action." }))

    result = @provider.fetch_account_data

    assert_not result.success?
    assert_includes result.error.message, "auth error"
  end

  # ── fetch_trade_history — Phase 1 multi-quote probe ──────────────────────────

  test "fetch_trade_history discovers asset that only has BTC-quoted trades (no USDT pair)" do
    eth_btc_trade = { "id" => 1, "symbol" => "ETHBTC", "price" => "0.05",
                      "qty" => "1.0", "isBuyer" => true, "time" => 1_700_000_000_000,
                      "commission" => "0.001", "commissionAsset" => "ETH" }

    client = mock
    @provider.stubs(:client).returns(client)

    # ETH has no USDT trades, but has BTC trades
    client.stubs(:my_trades).with(symbol: "ETHUSDT").returns([])
    client.stubs(:my_trades).with(symbol: "ETHBTC").returns([ eth_btc_trade ])
    client.stubs(:my_trades).with(symbol: "ETHETH").returns([])  # skipped (asset == quote)

    # Phase 2 — remaining quotes for ETH (USDT and BTC already fetched in Phase 1)
    %w[USDC BUSD FDUSD BNB EUR TRY BRL AUD RUB GBP USD].each do |q|
      client.stubs(:my_trades).with(symbol: "ETH#{q}").returns([])
    end

    balances = [ { "asset" => "ETH", "free" => "1.0", "locked" => "0.0" } ]
    result = @provider.fetch_trade_history(balances: balances)

    assert result.success?
    assert_includes result.data, eth_btc_trade
  end

  test "fetch_trade_history does not duplicate trades fetched in Phase 1" do
    btc_usdt_trade = { "id" => 2, "symbol" => "BTCUSDT", "price" => "50000",
                       "qty" => "0.1", "isBuyer" => true, "time" => 1_700_000_000_000,
                       "commission" => "0.0001", "commissionAsset" => "BTC" }

    client = mock
    @provider.stubs(:client).returns(client)

    # BTC has USDT trades (found in Phase 1)
    client.stubs(:my_trades).with(symbol: "BTCUSDT").returns([ btc_usdt_trade ])
    client.stubs(:my_trades).with(symbol: "BTCBTC").returns([])  # skipped (asset == quote)
    client.stubs(:my_trades).with(symbol: "BTCETH").returns([])

    # Phase 2 — USDT already fetched, BTC skipped (asset == quote)
    %w[USDC BUSD FDUSD BNB EUR TRY BRL AUD RUB GBP USD].each do |q|
      client.stubs(:my_trades).with(symbol: "BTC#{q}").returns([])
    end

    balances = [ { "asset" => "BTC", "free" => "0.1", "locked" => "0.0" } ]
    result = @provider.fetch_trade_history(balances: balances)

    assert result.success?
    assert_equal 1, result.data.count { |t| t["id"] == 2 }, "BTCUSDT trade must appear exactly once"
  end

  test "fetch_trade_history returns empty array when no trades found across all probe quotes" do
    client = mock
    @provider.stubs(:client).returns(client)

    Provider::Binance::PHASE1_PROBE_QUOTES.each do |quote|
      client.stubs(:my_trades).with(symbol: "SOL#{quote}").returns([])
    end

    balances = [ { "asset" => "SOL", "free" => "5.0", "locked" => "0.0" } ]
    result = @provider.fetch_trade_history(balances: balances)

    assert result.success?
    assert_empty result.data
  end
end
