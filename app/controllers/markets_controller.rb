class MarketsController < ApplicationController
  before_action :ensure_watchlist_defaults

  INDICES_CACHE_KEY = "markets/indices:v2".freeze
  INDICES_CACHE_TTL = 10.minutes
  MOVERS_CACHE_TTL = 10.minutes
  STOOQ_INDEX_SYMBOLS = {
    "^DJI" => "^dji",
    "^IXIC" => "^ndq",
    "^GSPC" => "^spx",
    "^FTSE" => "^ukx",
    "^GDAXI" => "^dax",
    "^FCHI" => "^cac",
    "000001.SS" => "^shc",
    "^HSI" => "^hsi",
    "^N225" => "^nkx"
  }.freeze
  EASTMONEY_INDEX_SYMBOLS = {
    "000001.SS" => "1.000001",
    "399001.SZ" => "0.399001",
    "899050.BJ" => "0.899050"
  }.freeze

  def stocks
    @watchlist = Current.family.watchlist_items.stocks.ordered
    @quotes, @quotes_error = fetch_stock_quotes(@watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def stocks_heatmap
    @top_gainers = fetch_market_movers("day_gainers")
    @top_losers = fetch_market_movers("day_losers")
    @market_news_source = params[:news_source].presence_in(%w[all cnbc seeking_alpha]) || "all"
    @market_news = filter_market_news(MarketNewsFeed.fetch, @market_news_source)
    @market_news = MarketNewsTranslator.translate_items(@market_news, locale: I18n.locale)
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
    log_indices_response(symbols: symbols, cached_result: cached_result, fetched_quotes: fetched_quotes, result: result)

    render json: result
  end

    private
    def fetch_indices_quotes(symbols)
      yahoo_quotes = fetch_indices_quotes_from_yahoo(symbols)
      result = yahoo_quotes.dup

      missing_symbols = symbols - result.keys
      eastmoney_quotes = missing_symbols.empty? ? {} : fetch_indices_quotes_from_eastmoney(missing_symbols)
      result.merge!(eastmoney_quotes)

      missing_symbols = symbols - result.keys
      nse_quotes = missing_symbols.empty? ? {} : fetch_indices_quotes_from_nse(missing_symbols)
      result.merge!(nse_quotes)

      missing_symbols = symbols - result.keys
      stooq_quotes = missing_symbols.empty? ? {} : fetch_indices_quotes_from_stooq(missing_symbols)
      result.merge!(stooq_quotes)

      result
    end

    def fetch_indices_quotes_from_yahoo(symbols)
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
        Rails.logger.warn("[Markets::Indices] upstream request failed status=#{res.code} body=#{res.body.to_s.first(200).inspect}")
        return {}
      end

      data = JSON.parse(res.body)
      quotes = data.dig("quoteResponse", "result") || []
      quote_map = quotes.each_with_object({}) do |quote, acc|
        symbol = quote["symbol"]
        price = quote["regularMarketPrice"]
        pct = quote["regularMarketChangePercent"]

        next if symbol.blank? || price.nil?

        acc[symbol] = {
          price: price,
          change_percent: pct&.round(2)
        }
      end
      missing_symbols = symbols - quote_map.keys
      Rails.logger.info("[Markets::Indices] upstream success source=yahoo quotes=#{quote_map.size}/#{symbols.size} missing=#{missing_symbols.join(',').presence || 'none'}")
      quote_map
    rescue => e
      Rails.logger.warn("[Markets::Indices] upstream exception source=yahoo class=#{e.class} message=#{e.message}")
      {}
    end

    def fetch_indices_quotes_from_stooq(symbols)
      supported_symbols = symbols.select { |symbol| STOOQ_INDEX_SYMBOLS.key?(symbol) }
      unsupported_symbols = symbols - supported_symbols

      if unsupported_symbols.any?
        Rails.logger.info("[Markets::Indices] fallback source=stooq unsupported=#{unsupported_symbols.join(',')}")
      end

      quote_map = supported_symbols.each_with_object({}) do |symbol, acc|
        quote = fetch_stooq_quote(symbol)
        acc[symbol] = quote if quote.present?
      end

      missing_symbols = supported_symbols - quote_map.keys
      Rails.logger.info("[Markets::Indices] fallback source=stooq quotes=#{quote_map.size}/#{supported_symbols.size} missing=#{missing_symbols.join(',').presence || 'none'}") if supported_symbols.any?
      quote_map
    end

    def fetch_indices_quotes_from_eastmoney(symbols)
      supported_symbols = symbols.select { |symbol| EASTMONEY_INDEX_SYMBOLS.key?(symbol) }
      unsupported_symbols = symbols - supported_symbols

      if unsupported_symbols.any?
        Rails.logger.info("[Markets::Indices] fallback source=eastmoney unsupported=#{unsupported_symbols.join(',')}")
      end

      return {} if supported_symbols.empty?

      uri = URI("https://push2.eastmoney.com/api/qt/ulist.np/get")
      uri.query = URI.encode_www_form(
        fields: "f2,f3,f12,f14",
        secids: supported_symbols.map { |symbol| EASTMONEY_INDEX_SYMBOLS.fetch(symbol) }.join(",")
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 1
      http.read_timeout = 2

      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0"
      req["Accept"] = "application/json"

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Markets::Indices] fallback source=eastmoney request failed status=#{res.code}")
        return {}
      end

      diff = JSON.parse(res.body).dig("data", "diff") || []
      code_map = EASTMONEY_INDEX_SYMBOLS.each_with_object({}) do |(symbol, secid), acc|
        acc[secid.split(".").last] = symbol
      end
      quote_map = diff.each_with_object({}) do |item, acc|
        local_symbol = code_map[item["f12"].to_s]
        next if local_symbol.blank?

        price = eastmoney_scaled_price(item["f2"])
        next if price.nil?

        acc[local_symbol] = {
          price: price,
          change_percent: eastmoney_scaled_percent(item["f3"])
        }
      end

      missing_symbols = supported_symbols - quote_map.keys
      Rails.logger.info("[Markets::Indices] fallback source=eastmoney quotes=#{quote_map.size}/#{supported_symbols.size} missing=#{missing_symbols.join(',').presence || 'none'}")
      quote_map
    rescue => e
      Rails.logger.warn("[Markets::Indices] fallback source=eastmoney exception class=#{e.class} message=#{e.message}")
      {}
    end

    def fetch_indices_quotes_from_nse(symbols)
      return {} unless symbols.include?("^NSEI")

      uri = URI("https://www.nseindia.com/api/allIndices")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 1
      http.read_timeout = 2

      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0"
      req["Accept"] = "application/json"

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Markets::Indices] fallback source=nse request failed status=#{res.code}")
        return {}
      end

      rows = JSON.parse(res.body).fetch("data", [])
      nifty = rows.find { |row| row["index"] == "NIFTY 50" || row["indexSymbol"] == "NIFTY 50" }
      return {} if nifty.blank? || nifty["last"].blank?

      quote = {
        "^NSEI" => {
          price: nifty["last"].to_f,
          change_percent: nifty["percentChange"]&.to_f&.round(2)
        }
      }
      Rails.logger.info("[Markets::Indices] fallback source=nse quotes=1/1 missing=none")
      quote
    rescue => e
      Rails.logger.warn("[Markets::Indices] fallback source=nse exception class=#{e.class} message=#{e.message}")
      {}
    end

    def fetch_stooq_quote(symbol)
      stooq_symbol = STOOQ_INDEX_SYMBOLS.fetch(symbol)
      uri = URI("https://stooq.com/q/l/")
      uri.query = URI.encode_www_form(s: stooq_symbol, i: "d", f: "sd2t2ohlcvpn", h: "1", e: "csv")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 1
      http.read_timeout = 2

      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = "Mozilla/5.0"
      req["Accept"] = "text/csv"

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Markets::Indices] fallback source=stooq request failed symbol=#{symbol} status=#{res.code}")
        return nil
      end

      rows = CSV.parse(res.body, headers: true)
      row = rows.first
      return nil if row.blank?

      close = numeric_csv_value(row["Close"])
      prev_close = numeric_csv_value(row["Prev"])
      return nil if close.nil?

      change_percent = if prev_close.present? && !prev_close.zero?
        (((close - prev_close) / prev_close) * 100).round(2)
      end

      {
        price: close,
        change_percent: change_percent
      }
    rescue => e
      Rails.logger.warn("[Markets::Indices] fallback source=stooq exception symbol=#{symbol} class=#{e.class} message=#{e.message}")
      nil
    end

    def numeric_csv_value(value)
      return nil if value.blank? || value == "N/D"

      BigDecimal(value).to_f
    rescue ArgumentError
      nil
    end

    def eastmoney_scaled_price(value)
      return nil if value.blank?

      value.to_f / 100.0
    end

    def eastmoney_scaled_percent(value)
      return nil if value.blank?

      (value.to_f / 100.0).round(2)
    end

    def log_indices_response(symbols:, cached_result:, fetched_quotes:, result:)
      source =
        if fetched_quotes.present?
          cached_result.present? ? "live+cache" : "live"
        elsif cached_result.present?
          "cache"
        else
          "empty"
        end

      missing_symbols = symbols - result.keys
      Rails.logger.info(
        "[Markets::Indices] response source=#{source} returned=#{result.size}/#{symbols.size} " \
        "live=#{fetched_quotes.size} cache=#{cached_result.size} missing=#{missing_symbols.join(',').presence || 'none'}"
      )
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

    def fetch_market_movers(screen_id)
      cache_key = "markets/movers:#{screen_id}:v1"
      cached = Rails.cache.read(cache_key)
      fresh = fetch_market_movers_from_yahoo(screen_id)

      if fresh.present?
        Rails.cache.write(cache_key, fresh, expires_in: MOVERS_CACHE_TTL)
        fresh
      else
        cached || []
      end
    end

    def fetch_market_movers_from_yahoo(screen_id)
      uri = URI("https://query1.finance.yahoo.com/v1/finance/screener/predefined/saved")
      uri.query = URI.encode_www_form(scrIds: screen_id, count: 10)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 2
      http.read_timeout = 5

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0"
      request["Accept"] = "application/json"

      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("Market movers fetch failed for #{screen_id}: HTTP #{response.code}")
        return []
      end

      quotes = JSON.parse(response.body).dig("finance", "result", 0, "quotes") || []

      quotes.filter_map do |quote|
        price = quote["regularMarketPrice"]
        next if quote["symbol"].blank? || price.nil?

        MarketQuote.new(
          symbol: quote["symbol"],
          name: quote["shortName"] || quote["longName"] || quote["symbol"],
          price: price,
          change_percent: quote["regularMarketChangePercent"],
          volume: quote["regularMarketVolume"],
          market_cap: quote["marketCap"],
          logo_url: "https://logo.synthfinance.com/ticker/#{quote['symbol']}",
          item_type: "stock",
          open_price: quote["regularMarketOpen"],
          prev_close: quote["regularMarketPreviousClose"],
          high: quote["regularMarketDayHigh"],
          low: quote["regularMarketDayLow"]
        )
      end
    rescue => e
      Rails.logger.warn("Market movers fetch failed for #{screen_id}: #{e.class}: #{e.message}")
      []
    end

    def filter_market_news(items, source)
      case source
      when "cnbc"
        items.select { |item| item.source == "CNBC" }
      when "seeking_alpha"
        items.select { |item| item.source == "Seeking Alpha" }
      else
        items
      end
    end
end
