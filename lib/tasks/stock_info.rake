namespace :stock_info do
  desc "Sync S&P 500 company info (sector, sub-industry) from Wikipedia into DB"
  task sync: :environment do
    count = StockInfo.sync_from_wikipedia!
    puts "Synced #{count} stock info records from Wikipedia."
  end

  desc "Translate all stock info descriptions to Chinese using Azure Translator"
  task translate_zh: :environment do
    records = StockInfo.where(description_zh: nil).where.not(sector: nil)
    puts "Translating #{records.count} records..."

    records.find_each do |record|
      record.translate_to_zh!
      print "."
    end

    puts "\nDone."
  end

  desc "Sync from Wikipedia then translate to Chinese"
  task setup: %i[sync translate_zh]
end
