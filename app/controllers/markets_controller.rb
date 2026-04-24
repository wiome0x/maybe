class MarketsController < ApplicationController
  before_action :ensure_watchlist_defaults

  INDICES_CACHE_KEY = "markets/indices:v2".freeze
  INDICES_CACHE_TTL = 10.minutes

  def stocks
    @watchlist = Current.family.watchlist_items.stocks.ordered
    @quotes, @quotes_error = fetch_stock_quotes(@watchlist)
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
    fetched_quotes = fetch_indices_quotes(symbols)
    result.merge!(fetched_quotes) if fetched_quotes.present?

    Rails.cache.write(INDICES_CACHE_KEY, result, expires_in: INDICES_CACHE_TTL) if fetched_quotes.present? && result.present?

    render json: result
  end

  private
    def fetch_indices_quotes(symbols)
      uri = URI("https://query1.finance.yahoo.com/v7/finance/quote")
      uri.query = URI.encode_www_form(symbols: symbols.join(","))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 5

      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0"
      req["Accept"] = "application/json"

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Indices fetch failed: HTTP #{res.code}")
        return {}
      end

      data = JSON.parse(res.body)
      quotes = data.dig("quoteResponse", "result") || []

      quotes.each_with_object({}) do |quote, acc|
        symbol = quote["symbol"]
        price = quote["regularMarketPrice"]
        pct = quote["regularMarketChangePercent"]

        next if symbol.blank? || price.nil?

        acc[symbol] = {
          price: price,
          change_percent: pct&.round(2)
        }
      end
    rescue => e
      Rails.logger.warn("Indices fetch failed: #{e.class}: #{e.message}")
      {}
    end

    def fetch_stock_quotes(watchlist)
      return [ [], nil ] if watchlist.empty?
      symbols = watchlist.pluck(:symbol)
      primary_result = Provider::Finnhub.new.fetch_market_data(symbols)
      return [ primary_result.data, nil ] if primary_result.success?

      fallback_result = Provider::YahooFinance.new.fetch_market_data(symbols)
      return [ fallback_result.data, nil ] if fallback_result.success?

      [ [], primary_result.error || fallback_result.error ]
    rescue => e
      Rails.logger.warn("Failed to fetch stock quotes: #{e.message}")
      [ [], e ]
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
