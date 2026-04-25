class Public::MarketsController < ApplicationController
  skip_authentication only: %i[stocks_heatmap stocks_news]
  layout "blank"

  MOVERS_CACHE_TTL = MarketsController::MOVERS_CACHE_TTL

  def stocks_heatmap
    @top_gainers = fetch_market_movers("day_gainers")
    @top_losers = fetch_market_movers("day_losers")
    @public_markets = true
    @breadcrumbs = [ [ t("markets.stocks_heatmap.title"), nil ] ]
    render "markets/stocks_heatmap"
  end

  def stocks_news
    load_market_news
    @public_markets = true
    @breadcrumbs = [ [ t("markets.stocks_news.title"), nil ] ]
    render "markets/stocks_news"
  end

  private
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
      return [] unless response.is_a?(Net::HTTPSuccess)

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
      Rails.logger.warn("Public market movers fetch failed for #{screen_id}: #{e.class}: #{e.message}")
      []
    end

    def filter_market_news(items, source)
      case source
      when "cnbc"
        items.select { |item| item.source == "CNBC" }
      when "seeking_alpha"
        items.select { |item| item.source == "Seeking Alpha" }
      when "sec"
        items.select { |item| item.source == "SEC" }
      when "bloomberg"
        items.select { |item| item.source == "Bloomberg" }
      when "marketwatch"
        items.select { |item| item.source == "MarketWatch" }
      when "fed"
        items.select { |item| item.source == "Fed" }
      else
        items
      end
    end

    def load_market_news
      @market_news_source = params[:news_source].presence_in(%w[all cnbc seeking_alpha sec bloomberg marketwatch fed]) || "all"
      MarketNewsArticle.refresh_if_stale!
      @market_news = filter_market_news(MarketNewsArticle.latest_feed, @market_news_source)
    end
end
