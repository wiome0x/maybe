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

  # HistoricalDataImport reads csv_rows directly in import!, so skip standard row generation
  def generate_rows_from_csv
    # no-op: we don't use the import_rows table
  end

  def sync_mappings
    # no-op: no mappings needed
  end

  def mapping_steps
    []
  end

  def dry_run
    { records: csv_rows.count }
  end

  # Skip standard cleaned/publishable checks since we don't use rows
  def configured?
    uploaded?
  end

  def cleaned?
    configured?
  end

  def publishable?
    cleaned? && !row_count_exceeded?
  end

  private

    # Override: HistoricalDataImport doesn't use the rows table,
    # so check csv_rows directly instead of rows.count
    def row_count_exceeded?
      csv_rows.count > max_row_count
    end

    def import!
      batch = []
      imported_count = 0

      csv_rows.each do |row|
        date = parse_date(row[date_col_label])
        close = parse_number(row[close_col_label])

        next if date.nil? || close.nil?

        ticker_value = row[ticker_col_label].to_s.strip
        next if ticker_value.blank?

        security = find_or_create_security(ticker: ticker_value)
        next unless security

        batch << {
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
        }

        if batch.size >= 500
          HistoricalPrice.upsert_all(batch, unique_by: %i[family_id security_id date])
          imported_count += batch.size
          batch = []
        end
      end

      if batch.any?
        HistoricalPrice.upsert_all(batch, unique_by: %i[family_id security_id date])
        imported_count += batch.size
      end

      raise "No valid records found. Please check your date format and column mappings." if imported_count == 0
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
