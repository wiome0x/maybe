class Provider::Finnhub < Provider
  BASE_URL = "https://finnhub.io/api/v1".freeze

  def initialize(api_key = nil)
    @api_key = api_key
  end

  def fetch_market_data(symbols)
    with_provider_response do
      raise ProviderError, "Finnhub API key not configured" if api_key.blank?

      quotes = symbols.map do |symbol|
        quote = get("/quote", { symbol: symbol })
        profile = get("/stock/profile2", { symbol: symbol })

        next if quote["c"].nil? || quote["c"].zero?

        prev_close = quote["pc"].to_f
        current = quote["c"].to_f
        change_pct = prev_close.zero? ? 0 : ((current - prev_close) / prev_close * 100).round(2)

        MarketQuote.new(
          symbol: symbol.upcase,
          name: profile["name"].presence || symbol,
          description: profile["finnhubIndustry"].presence,
          price: current,
          change_percent: change_pct,
          volume: quote["v"],
          market_cap: profile["marketCapitalization"].present? ? (profile["marketCapitalization"].to_f * 1_000_000).round : nil,
          logo_url: profile["logo"].presence || "https://logo.synthfinance.com/ticker/#{symbol}",
          item_type: "stock",
          open_price: quote["o"],
          prev_close: prev_close,
          high: quote["h"],
          low: quote["l"]
        )
      end.compact

      quotes
    end
  end

  def search_stocks(query)
    with_provider_response do
      raise ProviderError, "Finnhub API key not configured" if api_key.blank?

      response = get("/search", { q: query })
      (response["result"] || [])
        .select { |r| r["type"] == "Common Stock" }
        .first(10)
        .map { |r| { symbol: r["symbol"], name: r["description"] } }
    end
  end

  private
    def api_key
      @api_key.presence || ENV["FINNHUB_API_KEY"].presence || Setting.finnhub_api_key
    end

    def get(path, params = {})
      params[:token] = api_key
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"

      response = http.request(request)
      raise ProviderError, "Finnhub API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
end
