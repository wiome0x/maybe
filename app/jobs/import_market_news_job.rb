class ImportMarketNewsJob < ApplicationJob
  queue_as :scheduled

  def perform
    MarketNewsImporter.new.import
  end
end
