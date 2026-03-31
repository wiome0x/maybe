class HistoricalDataImport < Import
  has_many :historical_prices, foreign_key: :import_id, dependent: :destroy

  def revert
    Import.transaction do
      historical_prices.delete_all
      accounts.destroy_all
      entries.destroy_all
    end

    family.sync_later

    update! status: :pending
  rescue => error
    update! status: :revert_failed, error: error.message
  end

  def required_column_keys
    %i[date close ticker]
  end

  def column_keys
    %i[date open high low close volume ticker currency]
  end

  def max_row_count
    10_000
  end

  private

    def import!
      transaction do
        csv_rows.each do |row|
          date = parse_date(row[date_col_label])
          close = parse_number(row[close_col_label])

          next if date.nil? || close.nil?

          ticker_value = row[ticker_col_label].to_s.strip
          next if ticker_value.blank?

          security = find_or_create_security(ticker: ticker_value)
          next unless security

          HistoricalPrice.upsert(
            {
              family_id: family_id,
              security_id: security.id,
              import_id: id,
              date: date,
              open: parse_number(row[open_col_label]),
              high: parse_number(row[high_col_label]),
              low: parse_number(row[low_col_label]),
              close: close,
              volume: parse_number(row[volume_col_label]),
              ticker: ticker_value.upcase,
              currency: row[currency_col_label].presence || family.currency
            },
            unique_by: %i[family_id security_id date]
          )
        end
      end
    end

    def find_or_create_security(ticker: nil)
      return nil unless ticker.present?

      @security_cache ||= {}

      cache_key = ticker.strip.upcase

      security = @security_cache[cache_key]
      return security if security.present?

      security = Security::Resolver.new(ticker).resolve
      @security_cache[cache_key] = security

      security
    end

    def parse_date(value)
      return nil if value.blank?
      Date.strptime(value.to_s.strip, date_format)
    rescue Date::Error, ArgumentError
      nil
    end

    def parse_number(value)
      return nil if value.blank?
      sanitized = sanitize_number(value)
      return nil if sanitized.blank?
      BigDecimal(sanitized)
    rescue ArgumentError
      nil
    end

    # Column label accessors for CSV header mapping
    def close_col_label
      column_mappings&.dig("close") || "Close"
    end

    def open_col_label
      column_mappings&.dig("open") || "Open"
    end

    def high_col_label
      column_mappings&.dig("high") || "High"
    end

    def low_col_label
      column_mappings&.dig("low") || "Low"
    end

    def volume_col_label
      column_mappings&.dig("volume") || "Volume"
    end
end
