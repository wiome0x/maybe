MarketQuote = Data.define(
  :symbol,
  :name,
  :price,
  :change_percent,
  :volume,
  :market_cap,
  :logo_url,
  :item_type
) do
  def price_formatted
    return "N/A" if price.nil?
    price >= 1 ? sprintf("%.2f", price) : sprintf("%.4f", price)
  end

  def change_positive?
    (change_percent || 0) >= 0
  end

  def change_formatted
    return "0.00%" if change_percent.nil?
    "#{change_positive? ? '+' : ''}#{sprintf('%.2f', change_percent)}%"
  end

  def volume_formatted
    format_large_number(volume)
  end

  def market_cap_formatted
    format_large_number(market_cap)
  end

  private
    def format_large_number(num)
      return "N/A" if num.nil?
      if num >= 1_000_000_000_000
        "$#{sprintf('%.2f', num / 1_000_000_000_000.0)}T"
      elsif num >= 1_000_000_000
        "$#{sprintf('%.2f', num / 1_000_000_000.0)}B"
      elsif num >= 1_000_000
        "$#{sprintf('%.2f', num / 1_000_000.0)}M"
      else
        "$#{sprintf('%.2f', num)}"
      end
    end
end
