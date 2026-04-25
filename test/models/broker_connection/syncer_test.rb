require "test_helper"

class BrokerConnection::SyncerTest < ActiveSupport::TestCase
  setup do
    @broker_connection = broker_connections(:binance_connection)
    @sync = syncs(:account)
    @syncer = BrokerConnection::Syncer.new(@broker_connection)

    BrokerConnection::Processor.any_instance.stubs(:process)
  end

  # ---------------------------------------------------------------------------
  # Successful sync — Requirements 5 (AC 1, 2, 5)
  # ---------------------------------------------------------------------------

  test "successful sync updates account and transaction snapshots" do
    account_data = { "balances" => [] }
    trade_data = []

    mock_provider = mock("provider")
    mock_provider.stubs(:fetch_account_data).returns(OpenStruct.new(data: account_data))
    mock_provider.stubs(:fetch_trade_history).returns(OpenStruct.new(data: trade_data))

    @syncer.stubs(:build_provider).returns(mock_provider)
    @broker_connection.account.stubs(:sync_later)

    @broker_connection.expects(:upsert_account_snapshot!).with(account_data).once
    @broker_connection.expects(:upsert_transactions_snapshot!).with(trade_data).once

    @syncer.perform_sync(@sync)
  end

  test "successful sync triggers account.sync_later" do
    mock_provider = mock("provider")
    mock_provider.stubs(:fetch_account_data).returns(OpenStruct.new(data: {}))
    mock_provider.stubs(:fetch_trade_history).returns(OpenStruct.new(data: []))

    @syncer.stubs(:build_provider).returns(mock_provider)
    @broker_connection.stubs(:upsert_account_snapshot!)
    @broker_connection.stubs(:upsert_transactions_snapshot!)

    @broker_connection.account.expects(:sync_later).with(parent_sync: @sync).once

    @syncer.perform_sync(@sync)
  end

  # ---------------------------------------------------------------------------
  # Auth error — Requirements 5 (AC 4); Correctness Property 5
  # ---------------------------------------------------------------------------

  test "provider auth error sets status to requires_reauth and stores error message" do
    auth_error = Provider::Error.new("Binance auth error: invalid API key")

    mock_provider = mock("provider")
    mock_provider.stubs(:fetch_account_data).raises(auth_error)
    @syncer.stubs(:build_provider).returns(mock_provider)

    assert_raises(Provider::Error) { @syncer.perform_sync(@sync) }

    @broker_connection.reload
    assert_equal "requires_reauth", @broker_connection.status
    assert_equal auth_error.message, @broker_connection.error_message
  end

  # ---------------------------------------------------------------------------
  # Non-auth error — Requirements 5 (AC 3); Correctness Property 5
  # ---------------------------------------------------------------------------

  test "non-auth provider error sets status to error and is never active" do
    network_error = Provider::Error.new("Binance API error: HTTP 503 - Service Unavailable")

    mock_provider = mock("provider")
    mock_provider.stubs(:fetch_account_data).raises(network_error)
    @syncer.stubs(:build_provider).returns(mock_provider)

    assert_raises(Provider::Error) { @syncer.perform_sync(@sync) }

    @broker_connection.reload
    assert_equal "error", @broker_connection.status
    assert_equal network_error.message, @broker_connection.error_message
  end
end
