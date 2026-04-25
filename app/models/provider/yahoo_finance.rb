class Provider::YahooFinance < Provider
  BASE_URL = "https://query1.finance.yahoo.com".freeze

  def fetch_market_data(symbols)
    with_provider_response do
      return [] if symbols.empty?

      # Yahoo Finance v8 quote endpoint - free, no API key needed
      response = get("/v8/finance/spark", {
        symbols: symbols.join(","),
        range: "1d",
        interval: "5m"
      })

      quotes_response = get("/v7/finance/quote", {
        symbols: symbols.join(","),
        fields: "symbol,shortName,regularMarketPrice,regularMarketChangePercent,regularMarketVolume,marketCap"
      })

      result = quotes_response.dig("quoteResponse", "result") || []

      result.map do |quote|
        MarketQuote.new(
          symbol: quote["symbol"],
          name: quote["shortName"] || quote["longName"],
          description: nil,
          price: quote["regularMarketPrice"],
          change_percent: quote["regularMarketChangePercent"],
          volume: quote["regularMarketVolume"],
          market_cap: quote["marketCap"],
          logo_url: "https://logo.synthfinance.com/ticker/#{quote['symbol']}",
          item_type: "stock"
        )
      end
    end
  end

  def search_stocks(query)
    with_provider_response do
      response = get("/v1/finance/search", {
        q: query,
        quotesCount: 10,
        newsCount: 0,
        listsCount: 0
      })

      quotes = response.dig("quotes") || []
      quotes.select { |q| q["quoteType"] == "EQUITY" }.map do |q|
        { symbol: q["symbol"], name: q["shortname"] || q["longname"] }
      end
    end
  end

  private
    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0"
      request["Accept"] = "application/json"

      response = http.request(request)
      raise ProviderError, "Yahoo Finance API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
end
