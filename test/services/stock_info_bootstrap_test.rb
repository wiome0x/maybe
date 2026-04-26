require "test_helper"

class StockInfoBootstrapTest < ActiveSupport::TestCase
  test "does nothing when stock infos already exist" do
    StockInfo.stubs(:exists?).returns(true)
    SyncStockInfosJob.expects(:perform_later).never

    StockInfoBootstrap.perform!
  end

  test "enqueues sync when table is empty and lock is acquired" do
    StockInfo.stubs(:exists?).returns(false)
    connection = mock("connection")
    pool = mock("pool")

    ActiveRecord::Base.stubs(:connection_pool).returns(pool)
    pool.expects(:with_connection).yields(connection)
    connection.expects(:select_value).with(includes("pg_try_advisory_lock")).returns(true)
    connection.expects(:select_value).with(includes("pg_advisory_unlock")).returns(true)
    SyncStockInfosJob.expects(:perform_later).once

    StockInfoBootstrap.perform!
  end

  test "skips sync when lock is not acquired" do
    StockInfo.stubs(:exists?).returns(false)
    connection = mock("connection")
    pool = mock("pool")

    ActiveRecord::Base.stubs(:connection_pool).returns(pool)
    pool.expects(:with_connection).yields(connection)
    connection.expects(:select_value).with(includes("pg_try_advisory_lock")).returns(false)
    connection.expects(:select_value).with(includes("pg_advisory_unlock")).never
    SyncStockInfosJob.expects(:perform_later).never

    StockInfoBootstrap.perform!
  end
end
