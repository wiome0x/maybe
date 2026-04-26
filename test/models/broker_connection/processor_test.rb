require "test_helper"

class BrokerConnection::ProcessorTest < ActiveSupport::TestCase
  setup do
    @broker_connection = broker_connections(:binance_connection)
    @account = @broker_connection.account
    @processor = BrokerConnection::Processor.new(@broker_connection)

    @broker_connection.update!(
      raw_account_payload: {
        "balances" => [
          { "asset" => "BTC", "free" => "0.5000", "locked" => "0.1000" },
          { "asset" => "USDT", "free" => "25.0000", "locked" => "0.0000" }
        ]
      },
      raw_transactions_payload: [
        {
          "id" => 1001,
          "symbol" => "BTCUSDT",
          "price" => "30000.00",
          "qty" => "0.6000",
          "commission" => "12.00",
          "commissionAsset" => "USDT",
          "time" => Time.zone.parse("2026-04-24 10:00:00").to_i * 1000,
          "isBuyer" => true
        },
        {
          "id" => 1002,
          "symbol" => "BTCUSDT",
          "price" => "32000.00",
          "qty" => "0.1000",
          "commission" => "0.0005",
          "commissionAsset" => "BTC",
          "time" => Time.zone.parse("2026-04-25 10:00:00").to_i * 1000,
          "isBuyer" => false
        }
      ],
      last_snapshot_at: Time.zone.parse("2026-04-25 10:00:00")
    )
  end

  test "process imports binance trades with idempotency keys" do
    assert_difference -> { @account.trades.count }, 2 do
      @processor.process
    end

    buy_entry = @account.entries.find_by!(import_idempotency_key: "broker:binance:trade:1001")
    sell_entry = @account.entries.find_by!(import_idempotency_key: "broker:binance:trade:1002")

    assert_equal 0.6.to_d, buy_entry.trade.qty
    assert_equal(-0.1.to_d, sell_entry.trade.qty)
    assert_equal "USD", buy_entry.currency
  end

  test "process imports holdings snapshot from account balances" do
    @processor.process

    btc_holding = @account.holdings.joins(:security).find_by!(securities: { ticker: "BTC" })
    usdt_holding = @account.holdings.joins(:security).find_by!(securities: { ticker: "USDT" })

    assert_equal 0.6.to_d, btc_holding.qty
    # estimated_price uses the most recent trade price (sell at 32000)
    assert_equal 32_000.to_d, btc_holding.price
    assert_equal 25.to_d, usdt_holding.qty
    assert_equal 1.to_d, usdt_holding.price
  end

  test "process creates fee transactions once" do
    assert_difference -> { @account.transactions.count }, 2 do
      @processor.process
    end

    assert_no_difference -> { @account.transactions.count } do
      @processor.process
    end
  end
end
