require "test_helper"

class SyncStockInfosJobTest < ActiveJob::TestCase
  test "syncs stock infos when table is empty" do
    StockInfo.delete_all
    StockInfo.expects(:sync_from_wikipedia!).once

    SyncStockInfosJob.perform_now
  end

  test "skips sync when stock infos already exist" do
    StockInfo.stubs(:exists?).returns(true)
    StockInfo.expects(:sync_from_wikipedia!).never

    SyncStockInfosJob.perform_now
  end
end
