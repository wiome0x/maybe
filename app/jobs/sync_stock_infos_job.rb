class SyncStockInfosJob < ApplicationJob
  queue_as :low_priority

  def perform
    return if StockInfo.exists?

    StockInfo.sync_from_wikipedia!
  end
end
