class Provider::CurrencyApi < Provider
  include Provider::ExchangeRateConcept

  Error = Class.new(Provider::Error)

  BASE_URL = "https://cdn.jsdelivr.net/gh/ismartcoding/currency-api@main"

  # currency-api is always USD-based, so we convert via USD when needed:
  #   from -> USD -> to
  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      quotes = fetch_quotes_for_date(date)

      rate = convert_rate(quotes, from: from, to: to)

      raise Error, "No exchange rate found for #{from} -> #{to} on #{date}" if rate.nil?

      Rate.new(date: date.to_date, from: from, to: to, rate: rate)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      (start_date.to_date..end_date.to_date).filter_map do |date|
        quotes = fetch_quotes_for_date(date)
        next if quotes.nil?

        rate = convert_rate(quotes, from: from, to: to)
        next if rate.nil?

        Rate.new(date: date, from: from, to: to, rate: rate)
      end
    end
  end

  private

    # Fetch the quotes hash { "USD" => 1.0, "CNY" => 7.16, ... } for a given date.
    # Falls back to latest data if the specific date is unavailable.
    def fetch_quotes_for_date(date)
      url = "#{BASE_URL}/#{date}/0.json"
      response = Faraday.get(url)

      if response.success?
        parsed = JSON.parse(response.body)
        # Normalize: add base currency itself with rate 1.0
        parsed["quotes"].merge(parsed["base"] => 1.0)
      else
        # Fall back to latest snapshot
        fetch_latest_quotes
      end
    rescue => e
      Rails.logger.warn("Provider::CurrencyApi failed for #{date}: #{e.message}, falling back to latest")
      fetch_latest_quotes
    end

    def fetch_latest_quotes
      response = Faraday.get("#{BASE_URL}/latest/data.json")
      raise Error, "CurrencyApi latest data unavailable" unless response.success?

      parsed = JSON.parse(response.body)
      parsed["quotes"].merge(parsed["base"] => 1.0)
    end

    # currency-api is always USD-based.
    # To get from -> to: (1 / from_usd_rate) * to_usd_rate
    def convert_rate(quotes, from:, to:)
      from_rate = quotes[from]
      to_rate   = quotes[to]

      return nil if from_rate.nil? || to_rate.nil? || from_rate.zero?

      (to_rate / from_rate).round(6)
    end
end
