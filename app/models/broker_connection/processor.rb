class BrokerConnection::Processor
  BINANCE_KNOWN_QUOTES = %w[USDT USDC BUSD FDUSD USD BTC ETH BNB EUR TRY BRL AUD RUB GBP].freeze
  BINANCE_STABLE_QUOTES = %w[USD USDT USDC BUSD FDUSD].freeze

  # Schwab transaction types that represent equity trades
  SCHWAB_BUY_TYPES  = %w[BUY_TRADE RECEIVE_AND_DELIVER].freeze
  SCHWAB_SELL_TYPES = %w[SELL_TRADE].freeze
  SCHWAB_TRADE_TYPES = (SCHWAB_BUY_TYPES + SCHWAB_SELL_TYPES).freeze

  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def process
    if broker_connection.binance?
      process_holdings
      process_trades
      update_account_balance
    elsif broker_connection.schwab?
      process_schwab_holdings
      process_schwab_trades
      update_schwab_account_balance
    end
  end

  private
    def account
      broker_connection.account
    end

    # ─── Binance ────────────────────────────────────────────────────────────────

    def process_holdings
      return unless broker_connection.binance?

      snapshot_date = broker_connection.last_snapshot_at&.to_date || Date.current
      processed_keys = []

      binance_balances.each do |balance|
        asset = balance["asset"].to_s.upcase
        qty = total_balance_for(balance)
        next if asset.blank? || qty <= 0

        security = find_or_create_security!(asset)
        price = estimated_price_for(asset)
        amount = qty * price

        holding = account.holdings.find_or_initialize_by(
          security: security,
          date: snapshot_date,
          currency: account.currency
        )

        holding.assign_attributes(
          qty: qty,
          price: price,
          amount: amount
        )
        holding.save!

        processed_keys << [ security.id, account.currency ]
      end

      upsert_zero_quantity_holdings(snapshot_date:, processed_keys:)
    end

    def process_trades
      return unless broker_connection.binance?

      binance_trades.each do |trade_payload|
        upsert_trade_entry!(trade_payload)
        upsert_fee_entry!(trade_payload)
      end
    end

    def upsert_trade_entry!(trade_payload)
      security = find_or_create_security!(base_asset_for(trade_payload))
      qty = signed_qty_for(trade_payload)
      price = trade_payload["price"].to_d
      executed_on = trade_timestamp_for(trade_payload).to_date

      entry = account.entries.find_or_initialize_by(
        import_idempotency_key: trade_import_key(trade_payload)
      ) do |new_entry|
        new_entry.entryable = Trade.new
      end

      entry.assign_attributes(
        amount: qty * price,
        currency: normalized_trade_currency(trade_payload),
        date: executed_on,
        name: Trade.build_name(trade_type_for(trade_payload), qty, security.ticker)
      )

      entry.trade.assign_attributes(
        security: security,
        qty: qty,
        price: price,
        currency: normalized_trade_currency(trade_payload)
      )
      entry.save!
    end

    def upsert_fee_entry!(trade_payload)
      commission = trade_payload["commission"].to_d
      return if commission.zero?

      fee_asset = normalized_entry_currency(
        trade_payload["commissionAsset"].to_s.upcase.presence || normalized_trade_currency(trade_payload)
      )
      entry = account.entries.find_or_initialize_by(
        import_idempotency_key: fee_import_key(trade_payload)
      ) do |new_entry|
        new_entry.entryable = Transaction.new(kind: "funds_movement")
      end

      entry.assign_attributes(
        amount: commission.abs,
        currency: fee_asset,
        date: trade_timestamp_for(trade_payload).to_date,
        name: "Trading fee for #{trade_payload['symbol']}"
      )
      entry.transaction.kind = "funds_movement"
      entry.save!
    end

    def upsert_zero_quantity_holdings(snapshot_date:, processed_keys:)
      latest_holdings.each do |existing_holding|
        key = [ existing_holding.security_id, existing_holding.currency ]
        next if processed_keys.include?(key)

        zero_holding = account.holdings.find_or_initialize_by(
          security: existing_holding.security,
          date: snapshot_date,
          currency: existing_holding.currency
        )
        zero_holding.assign_attributes(
          qty: 0,
          price: existing_holding.price || 0,
          amount: 0
        )
        zero_holding.save!
      end
    end

    def latest_holdings
      account.holdings.where(
        id: account.holdings
          .select("DISTINCT ON (security_id, currency) id")
          .order(:security_id, :currency, date: :desc, created_at: :desc)
      )
    end

    def estimated_price_for(asset)
      if stable_asset?(asset)
        # Stable coins are pegged to USD. Convert 1 USD → account currency.
        return 1.to_d if account.currency == "USD"

        rate = ExchangeRate.find_or_fetch_rate(from: "USD", to: account.currency, date: Date.current)
        return rate.rate.to_d if rate.present?

        return 1.to_d # Fallback: treat as 1:1 if no rate available
      end

      trade = binance_trades.reverse.find do |payload|
        base_asset_for(payload) == asset && quote_asset_supported?(quote_asset_for(payload))
      end

      trade ? trade["price"].to_d : 0.to_d
    end

    def stable_asset?(asset)
      BINANCE_STABLE_QUOTES.include?(asset)
    end

    def quote_asset_supported?(quote_asset)
      quote_asset == account.currency || (account.currency == "USD" && BINANCE_STABLE_QUOTES.include?(quote_asset))
    end

    def total_balance_for(balance)
      balance["free"].to_d + balance["locked"].to_d
    end

    def signed_qty_for(trade_payload)
      qty = trade_payload["qty"].to_d.abs
      trade_payload["isBuyer"] ? qty : -qty
    end

    def trade_type_for(trade_payload)
      trade_payload["isBuyer"] ? "buy" : "sell"
    end

    def trade_timestamp_for(trade_payload)
      Time.zone.at(trade_payload["time"].to_i / 1000.0)
    end

    def normalized_trade_currency(trade_payload)
      normalized_entry_currency(quote_asset_for(trade_payload) || account.currency)
    end

    def base_asset_for(trade_payload)
      symbol = trade_payload["symbol"].to_s.upcase
      quote = quote_asset_for(trade_payload)
      return symbol if quote.blank?

      symbol.delete_suffix(quote)
    end

    def quote_asset_for(trade_payload)
      symbol = trade_payload["symbol"].to_s.upcase
      BINANCE_KNOWN_QUOTES.find { |candidate| symbol.end_with?(candidate) }
    end

    def normalized_entry_currency(currency)
      currency = currency.to_s.upcase
      return account.currency if account.currency == "USD" && BINANCE_STABLE_QUOTES.include?(currency)

      currency
    end

    def trade_import_key(trade_payload)
      "broker:#{broker_connection.provider}:trade:#{trade_payload['id']}"
    end

    def fee_import_key(trade_payload)
      "broker:#{broker_connection.provider}:trade_fee:#{trade_payload['id']}"
    end

    def find_or_create_security!(ticker)
      security = Security.find_or_create_by!(ticker: ticker.upcase) do |s|
        s.name = ticker.upcase
      end

      # Fetch logo + name from provider in the background if not yet populated
      security.import_provider_details_later if security.logo_url.blank?

      security
    end

    def binance_balances
      payload = broker_connection.raw_account_payload
      payload.is_a?(Hash) ? payload.fetch("balances", []) : []
    end

    def binance_trades
      Array(broker_connection.raw_transactions_payload)
    end

    # After processing holdings, set the current_anchor valuation so the
    # reverse balance calculator has a starting point.
    def update_account_balance
      total = binance_balances.sum do |b|
        asset = b["asset"].to_s.upcase
        qty   = total_balance_for(b)
        next 0 if qty <= 0

        if stable_asset?(asset)
          qty * estimated_price_for(asset)
        else
          holding = account.holdings.find_by(
            security: Security.find_by(ticker: asset),
            date: broker_connection.last_snapshot_at&.to_date || Date.current
          )
          holding ? holding.amount : 0
        end
      end

      account.set_current_balance(total.to_d)
    end

    # ─── Schwab ─────────────────────────────────────────────────────────────────

    def process_schwab_holdings
      snapshot_date = broker_connection.last_snapshot_at&.to_date || Date.current
      processed_keys = []

      schwab_positions.each do |position|
        instrument = position.dig("instrument") || {}
        symbol = instrument["symbol"].to_s.upcase
        asset_type = instrument["assetType"].to_s

        # Only process equity positions (skip options, fixed income, etc.)
        next if symbol.blank? || asset_type == "OPTION"

        qty = position["longQuantity"].to_d - position["shortQuantity"].to_d
        market_value = position["marketValue"].to_d
        price = qty.nonzero? ? (market_value / qty).abs : position["currentDayProfitLossPercentage"].to_d

        security = find_or_create_security!(symbol)

        holding = account.holdings.find_or_initialize_by(
          security: security,
          date: snapshot_date,
          currency: account.currency
        )
        holding.assign_attributes(qty: qty, price: price, amount: market_value.abs)
        holding.save!

        processed_keys << [ security.id, account.currency ]
      end

      upsert_zero_quantity_holdings(snapshot_date:, processed_keys:)
    end

    def process_schwab_trades
      schwab_transactions.each do |txn|
        type = txn["type"].to_s
        next unless SCHWAB_TRADE_TYPES.include?(type)

        item = txn["transactionItem"] || {}
        instrument = item["instrument"] || {}
        symbol = instrument["symbol"].to_s.upcase
        asset_type = instrument["assetType"].to_s

        next if symbol.blank? || asset_type == "OPTION"

        qty_raw = item["amount"].to_d.abs
        price = item["price"].to_d
        date = parse_schwab_date(txn["transactionDate"])
        txn_id = txn["transactionId"].to_s

        is_buy = SCHWAB_BUY_TYPES.include?(type)
        qty = is_buy ? qty_raw : -qty_raw
        trade_type = is_buy ? "buy" : "sell"

        security = find_or_create_security!(symbol)

        entry = account.entries.find_or_initialize_by(
          import_idempotency_key: "broker:schwab:trade:#{txn_id}"
        ) do |new_entry|
          new_entry.entryable = Trade.new
        end

        entry.assign_attributes(
          amount: qty * price,
          currency: account.currency,
          date: date,
          name: Trade.build_name(trade_type, qty, security.ticker)
        )
        entry.trade.assign_attributes(
          security: security,
          qty: qty,
          price: price,
          currency: account.currency
        )
        entry.save!

        # Schwab charges commission separately — upsert as a fee transaction if present
        fees = txn["fees"]
        if fees.is_a?(Hash)
          commission = fees.values.sum(&:to_d)
          if commission > 0
            fee_entry = account.entries.find_or_initialize_by(
              import_idempotency_key: "broker:schwab:trade_fee:#{txn_id}"
            ) do |new_entry|
              new_entry.entryable = Transaction.new(kind: "funds_movement")
            end
            fee_entry.assign_attributes(
              amount: commission,
              currency: account.currency,
              date: date,
              name: "Trading fee for #{symbol}"
            )
            fee_entry.transaction.kind = "funds_movement"
            fee_entry.save!
          end
        end
      end
    end

    def update_schwab_account_balance
      # Sum market values of all current positions
      total = schwab_positions.sum do |position|
        position["marketValue"].to_d.abs
      end

      # Add cash balance if present
      cash = schwab_account_payload.dig("securitiesAccount", "currentBalances", "cashBalance").to_d
      account.set_current_balance((total + cash).to_d)
    end

    def schwab_positions
      Array(schwab_account_payload.dig("securitiesAccount", "positions"))
    end

    def schwab_account_payload
      payload = broker_connection.raw_account_payload
      payload.is_a?(Hash) ? payload : {}
    end

    def schwab_transactions
      Array(broker_connection.raw_transactions_payload)
    end

    def parse_schwab_date(value)
      return Date.current if value.blank?

      # Schwab returns ISO8601 datetime strings like "2024-01-15T10:30:00+0000"
      Time.parse(value).to_date
    rescue ArgumentError
      Date.current
    end
end
