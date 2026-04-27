class ImportMarketNewsJob < ApplicationJob
  queue_as :scheduled

  def perform
    track_run("import_market_news") do |run|
      count = MarketNewsImporter.new.import
      run.records_written = count
    end
  end
end
