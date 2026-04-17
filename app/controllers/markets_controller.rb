class MarketsController < ApplicationController
  before_action :ensure_watchlist_defaults

  INDICES_CACHE_KEY = "markets/indices:v2".freeze
  INDICES_CACHE_TTL = 10.minutes

  def stocks
    watchlist = Current.family.watchlist_items.stocks.ordered
    @quotes = fetch_stock_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def stocks_heatmap
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def cryptos
    watchlist = Current.family.watchlist_items.cryptos.ordered
    @quotes = fetch_crypto_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def indices
    symbols = %w[
      ^DJI
      ^IXIC
      ^GSPC
      ^FTSE
      ^GDAXI
      ^FCHI
      000001.SS
      899050.BJ
      ^HSI
      ^N225
      399001.SZ
      ^NSEI
      ^VNINDEX
      ^AXJO
      ^BVSP
    ]
    cached_result = Rails.cache.read(INDICES_CACHE_KEY) || {}
    result = cached_result.deep_dup
    fetched_any = false

    symbols.each do |symbol|
      begin
        uri = URI("https://query1.finance.yahoo.com/v8/finance/chart/#{CGI.escape(symbol)}?range=1d&interval=1d")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 2
        http.read_timeout = 3

        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = "Mozilla/5.0"
        req["Accept"] = "application/json"
        res = http.request(req)

        next unless res.is_a?(Net::HTTPSuccess)
        data = JSON.parse(res.body)
        meta = data.dig("chart", "result", 0, "meta")
        next unless meta

        price = meta["regularMarketPrice"]
        prev = meta["chartPreviousClose"] || meta["previousClose"]
        pct = prev && prev > 0 ? ((price - prev) / prev * 100).round(2) : nil

        result[symbol] = { price: price, change_percent: pct }
        fetched_any = true
      rescue => e
        Rails.logger.debug("Index fetch failed for #{symbol}: #{e.message}")
      end
    end

    Rails.cache.write(INDICES_CACHE_KEY, result, expires_in: INDICES_CACHE_TTL) if fetched_any && result.present?

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
