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

  # Bilingual section names (Chinese / English)
  INSTRUMENT_SECTIONS = [ "金融产品信息", "Financial Instrument Information" ].freeze
  TRADE_SECTIONS      = [ "交易", "Trades" ].freeze
  STOCK_CLASSES        = [ "股票", "Stocks" ].freeze
  DEPOSIT_SECTIONS    = [ "存款和取款", "Deposits & Withdrawals" ].freeze
  DIVIDEND_SECTIONS   = [ "股息", "Dividends" ].freeze
  GRANT_SECTIONS      = [ "股票赠与活动", "Stock Grant Activity" ].freeze
  WITHHOLDING_SECTIONS = [ "代扣税", "Withholding Tax" ].freeze

  # Row entity_type values to distinguish row kinds
  ENTITY_TRADE      = "trade".freeze
  ENTITY_DEPOSIT    = "deposit".freeze
  ENTITY_DIVIDEND   = "dividend".freeze
  ENTITY_GRANT      = "grant".freeze
  ENTITY_TAX        = "tax".freeze

  def generate_rows_from_csv
    rows.destroy_all

    parsed = parse_ibkr_statement
    mapped_rows = parsed.map do |row|
      {
        date: row[:date],
        ticker: row[:ticker].to_s,
        exchange_operating_mic: row[:exchange_operating_mic].to_s,
        qty: row[:qty].to_s,
        price: row[:price].to_s,
        amount: row[:amount].to_s,
        currency: row[:currency],
        name: row[:name],
        entity_type: row[:entity_type],
        account: ""
      }
    end

    rows.insert_all!(mapped_rows) if mapped_rows.any?
  end

  def import!
    transaction do
      mappings.each(&:create_mappable!)

      trade_rows = rows.where(entity_type: [ ENTITY_TRADE, ENTITY_GRANT ])
      cash_rows  = rows.where(entity_type: [ ENTITY_DEPOSIT, ENTITY_DIVIDEND, ENTITY_TAX ])

      import_trades(trade_rows) if trade_rows.any?
      import_cash_entries(cash_rows) if cash_rows.any?
    end
  end

  def mapping_steps
    base = []
    base << Import::AccountMapping if account.nil?
    base
  end

  def required_column_keys
    []
  end

  def column_keys
    base = %i[date ticker exchange_operating_mic currency qty price amount name entity_type]
    base.unshift(:account) if account.nil?
    base
  end

  def dry_run
    trade_count    = rows.where(entity_type: ENTITY_TRADE).count
    deposit_count  = rows.where(entity_type: ENTITY_DEPOSIT).count
    dividend_count = rows.where(entity_type: ENTITY_DIVIDEND).count
    grant_count    = rows.where(entity_type: ENTITY_GRANT).count
    tax_count      = rows.where(entity_type: ENTITY_TAX).count

    result = { transactions: trade_count }
    result[:deposits] = deposit_count if deposit_count > 0
    result[:dividends] = dividend_count if dividend_count > 0
    result[:grants] = grant_count if grant_count > 0
    result[:taxes] = tax_count if tax_count > 0
    result
  end

  def csv_template
    template = <<-CSV
      date,ticker,exchange_operating_mic,currency,qty,price,amount,name,entity_type
      2026-03-02,QQQM,XNAS,USD,0.2012,248.47,,Buy QQQM,trade
      2026-03-02,TSLA,XNAS,USD,0.1,390.40,,Buy TSLA,trade
      2026-02-21,,,,,,500,Deposit HKD,deposit
      2026-03-27,,,,,,0.07,Dividend QQQM,dividend
    CSV

    CSV.parse(template, headers: true)
  end

  private

    def mapped_account_for(row)
      if account
        account
      else
        mappings.accounts.mappable_for(row.account)
      end
    end

    def import_trades(trade_rows)
      trades = trade_rows.filter_map do |row|
        mapped = mapped_account_for(row)
        currency = row.currency.presence || mapped.currency
        amount = row.signed_amount
        key = idempotency_key(mapped.id, row.date_iso, amount, currency, row.name, row.entity_type)

        next if entry_exists?(mapped.id, key)

        security = find_or_create_security(
          ticker: row.ticker,
          exchange_operating_mic: row.exchange_operating_mic
        )

        Trade.new(
          security: security,
          qty: row.qty,
          currency: currency,
          price: row.price,
          entry: Entry.new(
            account: mapped,
            date: row.date_iso,
            amount: amount,
            name: row.name,
            currency: currency,
            import: self,
            import_idempotency_key: key
          )
        )
      end

      Trade.import!(trades, recursive: true) if trades.any?
    end

    def import_cash_entries(cash_rows)
      transactions = cash_rows.filter_map do |row|
        mapped = mapped_account_for(row)
        currency = row.currency.presence || mapped.currency

        amount = row.amount.to_d
        signed = case row.entity_type
        when ENTITY_DEPOSIT
          amount.negative? ? amount : -amount.abs
        when ENTITY_DIVIDEND, ENTITY_GRANT
          -amount.abs
        when ENTITY_TAX
          amount.abs
        else
          amount
        end

        key = idempotency_key(mapped.id, row.date_iso, signed, currency, row.name, row.entity_type)

        next if entry_exists?(mapped.id, key)

        Transaction.new(
          entry: Entry.new(
            account: mapped,
            date: row.date_iso,
            amount: signed,
            name: row.name,
            currency: currency,
            import: self,
            import_idempotency_key: key
          )
        )
      end

      Transaction.import!(transactions, recursive: true) if transactions.any?
    end

    # Deterministic key: SHA256 of account + date + amount + currency + name + entity_type
    def idempotency_key(account_id, date, amount, currency, name, entity_type)
      Digest::SHA256.hexdigest([ account_id, date.to_s, amount.to_s, currency.to_s, name.to_s, entity_type.to_s ].join("|"))
    end

    # Check DB directly to avoid loading all entries into memory
    def entry_exists?(account_id, key)
      @existing_keys ||= Entry.where(account_id: account_id)
                              .where.not(import_idempotency_key: nil)
                              .pluck(:import_idempotency_key)
                              .to_set
      @existing_keys.include?(key)
    end

    def set_mappings
      self.date_col_label = "date"
      self.date_format = "%Y-%m-%d"
      self.ticker_col_label = "ticker"
      self.exchange_operating_mic_col_label = "exchange_operating_mic"
      self.currency_col_label = "currency"
      self.qty_col_label = "qty"
      self.price_col_label = "price"
      self.amount_col_label = "amount"
      self.name_col_label = "name"
      self.signage_convention = "inflows_positive"

      save!
    end

    def parse_ibkr_statement
      instrument_mics = {}
      results = []

      raw_lines = (raw_file_str || "").lines

      # First pass: collect instrument exchange info
      raw_lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        if INSTRUMENT_SECTIONS.include?(row[0]&.strip) && row[1]&.strip == "Data"
          ticker = row[3]&.strip
          exchange = row[7]&.strip
          instrument_mics[ticker] = EXCHANGE_MIC_MAP[exchange] || exchange if ticker && exchange
        end
      end

      # Second pass: extract all data
      raw_lines.each do |line|
        row = CSV.parse_line(line)
        next if row.nil? || row.empty?

        section = row[0]&.strip
        discriminator = row[1]&.strip
        next unless discriminator == "Data"

        if TRADE_SECTIONS.include?(section)
          parse_trade_row(row, instrument_mics, results)
        elsif DEPOSIT_SECTIONS.include?(section)
          parse_deposit_row(row, results)
        elsif DIVIDEND_SECTIONS.include?(section)
          parse_dividend_row(row, results)
        elsif GRANT_SECTIONS.include?(section)
          parse_grant_row(row, instrument_mics, results)
        elsif WITHHOLDING_SECTIONS.include?(section)
          parse_withholding_row(row, results)
        end
      end

      results
    end

    def parse_trade_row(row, instrument_mics, results)
      data_type = row[2]&.strip
      return unless data_type == "Order"

      asset_class = row[3]&.strip
      return unless STOCK_CLASSES.include?(asset_class)

      currency = row[4]&.strip
      ticker = row[5]&.strip
      datetime = row[6]&.strip
      qty = row[7]&.to_f
      price = row[8]&.to_f

      return if ticker.blank?

      date = datetime&.split(",")&.first&.strip

      results << {
        date: date,
        ticker: ticker,
        exchange_operating_mic: instrument_mics[ticker] || "XNAS",
        currency: currency,
        qty: qty,
        price: price,
        name: "#{qty > 0 ? 'Buy' : 'Sell'} #{ticker}",
        entity_type: ENTITY_TRADE
      }
    end

    # CSV format: 存款和取款,Data,<currency>,<date>,<description>,<amount>
    def parse_deposit_row(row, results)
      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      # Skip summary/total rows
      return if currency&.start_with?("总数", "Total")
      return if date.blank? || amount == 0

      results << {
        date: date,
        currency: currency,
        amount: amount,
        name: description.presence || (amount > 0 ? "Deposit" : "Withdrawal"),
        entity_type: ENTITY_DEPOSIT
      }
    end

    # CSV format: 股息,Data,<currency>,<date>,<description>,<amount>
    def parse_dividend_row(row, results)
      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      return if currency&.start_with?("总数", "Total")
      return if date.blank? || amount == 0

      # Extract ticker from description like "QQQM(US46138G6492) 现金红利..."
      ticker = description&.match(/\A(\w+)\(/)&.captures&.first

      results << {
        date: date,
        currency: currency,
        amount: amount,
        name: "Dividend #{ticker}".strip,
        entity_type: ENTITY_DIVIDEND
      }
    end

    # CSV format: 股票赠与活动,Data,<ticker>,<date>,<description>,<award_date>,<vest_date>,<qty>,<price>,<value>
    def parse_grant_row(row, instrument_mics, results)
      ticker = row[2]&.strip
      date = row[3]&.strip
      qty = row[7]&.to_f
      price = row[8]&.to_f
      value = row[9]&.to_f

      # Skip summary/total rows
      return if ticker&.start_with?("总数", "Total")
      return if date.blank? || qty == 0

      results << {
        date: date,
        ticker: ticker,
        exchange_operating_mic: instrument_mics[ticker] || "XNAS",
        currency: "USD",
        qty: qty,
        price: price,
        amount: value,
        name: "Stock grant #{ticker}",
        entity_type: ENTITY_GRANT
      }
    end

    # CSV format: 代扣税,Data,<currency>,<date>,<description>,<amount>,<code>
    def parse_withholding_row(row, results)
      currency = row[2]&.strip
      date = row[3]&.strip
      description = row[4]&.strip
      amount = row[5]&.to_f

      return if currency&.start_with?("总数", "Total")
      return if date.blank? || amount == 0

      ticker = description&.match(/\A(\w+)\(/)&.captures&.first

      results << {
        date: date,
        currency: currency,
        amount: amount.abs,
        name: "Withholding tax #{ticker}".strip,
        entity_type: ENTITY_TAX
      }
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
