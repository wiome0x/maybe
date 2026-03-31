class MarketsController < ApplicationController
  before_action :ensure_watchlist_defaults

  def stocks
    watchlist = Current.family.watchlist_items.stocks.ordered
    @quotes = fetch_stock_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def cryptos
    watchlist = Current.family.watchlist_items.cryptos.ordered
    @quotes = fetch_crypto_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def indices
    symbols = %w[000001.SS ^HSI ^GSPC ^IXIC ^DJI ^GDAXI ^FTSE ^N225]
    result = {}

    symbols.each do |symbol|
      begin
        uri = URI("https://query1.finance.yahoo.com/v8/finance/chart/#{CGI.escape(symbol)}?range=1d&interval=1d")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 5

        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "Mozilla/5.0"
        res = http.request(req)

        next unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        meta = data.dig("chart", "result", 0, "meta")
        next unless meta

        price = meta["regularMarketPrice"]
        prev = meta["chartPreviousClose"] || meta["previousClose"]
        pct = prev && prev > 0 ? ((price - prev) / prev * 100).round(2) : nil

        result[symbol] = { price: price, change_percent: pct }
      rescue => e
        Rails.logger.debug("Index fetch failed for #{symbol}: #{e.message}")
      end
    end

    render json: result
  end

  private
    def fetch_stock_quotes(watchlist)
      return [] if watchlist.empty?
      symbols = watchlist.pluck(:symbol)
      provider = Provider::Finnhub.new
      result = provider.fetch_market_data(symbols)
      result.success? ? result.data : []
    rescue => e
      Rails.logger.warn("Failed to fetch stock quotes: #{e.message}")
      []
    end

    def fetch_crypto_quotes(watchlist)
      return [] if watchlist.empty?
      symbols = watchlist.pluck(:symbol)
      provider = Provider::Coingecko.new
      result = provider.fetch_market_data(symbols)
      result.success? ? result.data : []
    rescue => e
      Rails.logger.warn("Failed to fetch crypto quotes: #{e.message}")
      []
    end

    def ensure_watchlist_defaults
      WatchlistItem.seed_defaults_for(Current.family)
    end
end
