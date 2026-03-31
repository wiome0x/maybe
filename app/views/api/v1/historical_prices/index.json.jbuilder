# frozen_string_literal: true

json.historical_prices @historical_prices do |price|
  json.date price.date
  json.open price.open
  json.high price.high
  json.low price.low
  json.close price.close
  json.volume price.volume
  json.ticker price.ticker
  json.currency price.currency
end

json.pagination do
  json.page @pagy.page
  json.per_page @pagy.limit
  json.total_count @pagy.count
  json.total_pages @pagy.pages
end
