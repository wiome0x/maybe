class IbkrImport < Import
  after_create :set_mappings

  EXCHANGE_MIC_MAP = {
    "NASDAQ" => "XNAS",
    "NYSE" => "XNYS",
    "ARCA" => "ARCX",
    "AMEX" => "XASE",
    "BATS" => "BATS",
    "IEX" => "IEXG",
    "LSE" => "XLON",
    "TSE" => "XTSE",
    "HKEX" => "XHKG",
    "SGX" => "XSES"
  }.freeze

  def generate_rows_from_csv
    rows.destroy_all

    parsed = parse_ibkr_statement
    mapped_rows = parsed.map do |row|
      {
        date: row[:date],
        ticker: row[:ticker],
        exchange_operating_mic: row[:exchange_operating_mic],
        qty: row[:qty].to_s,
        price: row[:price].to_s,
        currency: row[:currency],
        name: row[:name],
        account: ""
      }
    end

    rows.insert_all!(mapped_rows) if mapped_rows.any?
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      trades = rows.map do |row|
        mapped_account = if account
          account
        else
          mappings.accounts.mappable_for(row.account)
        end

        security = find_or_create_security(
          ticker: row.ticker,
          exchange_operating_mic: row.exchange_operating_mic
        )

        Trade.new(
          security: security,
          qty: row.qty,
          currency: row.currency.presence || mapped_account.currency,
          price: row.price,
          entry: Entry.new(
            account: mapped_account,
            date: row.date_iso,
            amount: row.signed_amount,
            name: row.name,
            currency: row.currency.presence || mapped_account.currency,
            import: self
          ),
        )
      end

      Trade.import!(trades, recursive: true)
    end
  end

  def mapping_steps
    base = []
    base << Import::AccountMapping if account.nil?
    base
  end

  def required_column_keys
    %i[date ticker qty price]
  end

  def column_keys
    base = %i[date ticker exchange_operating_mic currency qty price name]
    base.unshift(:account) if account.nil?
    base
  end

  def dry_run
    { transactions: rows.count }
  end

  def csv_template
    template = <<-CSV
      date,ticker,exchange_operating_mic,currency,qty,price,name
      2026-03-02,QQQM,XNAS,USD,0.2012,248.47,Buy QQQM
      2026-03-02,TSLA,XNAS,USD,0.1,390.40,Buy TSLA
    CSV

    CSV.parse(template, headers: true)
  end

  private

    def set_mappings
      self.date_col_label = "date"
      self.date_format = "%Y-%m-%d"
      self.ticker_col_label = "ticker"
      self.exchange_operating_mic_col_label = "exchange_operating_mic"
      self.currency_col_label = "currency"
      self.qty_col_label = "qty"
      self.price_col_label = "price"
      self.name_col_label = "name"
      self.signage_convention = "inflows_positive"

      save!
    end

    def parse_ibkr_statement
      instrument_mics = {}
      trades = []

      raw_lines = (raw_file_str || "").lines

      # First pass: collect instrument exchange info
      raw_lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        if row[0]&.strip == "金融产品信息" && row[1]&.strip == "Data"
          ticker = row[3]&.strip
          exchange = row[7]&.strip
          instrument_mics[ticker] = EXCHANGE_MIC_MAP[exchange] || exchange if ticker && exchange
        end
      end

      # Second pass: extract stock trades
      raw_lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        section = row[0]&.strip
        discriminator = row[1]&.strip
        next unless section == "交易" && discriminator == "Data"

        data_type = row[2]&.strip
        next unless data_type == "Order"

        asset_class = row[3]&.strip
        next unless asset_class == "股票"

        currency = row[4]&.strip
        ticker = row[5]&.strip
        datetime = row[6]&.strip
        qty = row[7]&.to_f
        price = row[8]&.to_f

        next if ticker.nil? || ticker.empty?

        date = datetime&.split(",")&.first&.strip

        trades << {
          date: date,
          ticker: ticker,
          exchange_operating_mic: instrument_mics[ticker] || "XNAS",
          currency: currency,
          qty: qty,
          price: price,
          name: "#{qty > 0 ? 'Buy' : 'Sell'} #{ticker}"
        }
      end

      trades
    end

    def find_or_create_security(ticker: nil, exchange_operating_mic: nil)
      return nil unless ticker.present?

      @security_cache ||= {}
      cache_key = [ ticker, exchange_operating_mic ].compact.join(":")
      return @security_cache[cache_key] if @security_cache[cache_key].present?

      security = Security::Resolver.new(
        ticker,
        exchange_operating_mic: exchange_operating_mic.presence
      ).resolve

      @security_cache[cache_key] = security
      security
    end
end
