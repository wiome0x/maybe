class Provider::Coingecko < Provider
  BASE_URL = "https://api.coingecko.com/api/v3".freeze

  # Map common crypto symbols to CoinGecko IDs
  SYMBOL_TO_ID = {
    "BTC" => "bitcoin", "ETH" => "ethereum", "USDT" => "tether",
    "BNB" => "binancecoin", "XRP" => "ripple", "USDC" => "usd-coin",
    "SOL" => "solana", "ADA" => "cardano", "DOGE" => "dogecoin",
    "TRX" => "tron", "DOT" => "polkadot", "MATIC" => "matic-network",
    "LTC" => "litecoin", "SHIB" => "shiba-inu", "AVAX" => "avalanche-2",
    "LINK" => "chainlink", "UNI" => "uniswap", "ATOM" => "cosmos",
    "XLM" => "stellar", "BCH" => "bitcoin-cash", "WBTC" => "wrapped-bitcoin",
    "ETC" => "ethereum-classic", "FIL" => "filecoin", "APT" => "aptos",
    "ARB" => "arbitrum", "OP" => "optimism", "SUI" => "sui"
  }.freeze

  def fetch_market_data(symbols)
    with_provider_response do
      ids = symbols.map { |s| SYMBOL_TO_ID[s.upcase] }.compact
      return [] if ids.empty?

      response = get("/coins/markets", {
        vs_currency: "usd",
        ids: ids.join(","),
        order: "market_cap_desc",
        per_page: 250,
        page: 1,
        sparkline: false,
        price_change_percentage: "24h"
      })

      response.map do |coin|
        symbol = coin["symbol"]&.upcase
        MarketQuote.new(
          symbol: symbol,
          name: coin["name"],
          description: nil,
          price: coin["current_price"],
          change_percent: coin["price_change_percentage_24h"],
          volume: coin["total_volume"],
          market_cap: coin["market_cap"],
          logo_url: coin["image"],
          item_type: "crypto",
          open_price: nil,
          prev_close: nil,
          high: coin["high_24h"],
          low: coin["low_24h"]
        )
      end
    end
  end

  def search_coins(query)
    with_provider_response do
      response = get("/search", { query: query })
      (response["coins"] || []).first(10).map do |coin|
        { symbol: coin["symbol"]&.upcase, name: coin["name"], id: coin["id"], logo_url: coin["large"] }
      end
    end
  end

  def coingecko_id_for(symbol)
    SYMBOL_TO_ID[symbol.upcase]
  end

  private
    def get(path, params = {})
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(params)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["x-cg-demo-api-key"] = ENV["COINGECKO_API_KEY"] if ENV["COINGECKO_API_KEY"].present?

      response = http.request(request)
      raise ProviderError, "CoinGecko API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
end
