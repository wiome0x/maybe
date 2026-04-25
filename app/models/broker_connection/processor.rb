class BrokerConnection::Processor
  BINANCE_KNOWN_QUOTES = %w[USDT USDC BUSD FDUSD USD BTC ETH BNB EUR TRY BRL AUD RUB GBP].freeze
  BINANCE_STABLE_QUOTES = %w[USD USDT USDC BUSD FDUSD].freeze

  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def process
    process_holdings
    process_trades
  end

  private
    def account
      broker_connection.account
    end

    def process_holdings
      return unless broker_connection.binance?

      snapshot_date = broker_connection.last_snapshot_at&.to_date || Date.current
      processed_keys = []

      binance_balances.each do |balance|
        asset = balance["asset"].to_s.upcase
        qty = total_balance_for(balance)
        next if asset.blank?

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
      return 1.to_d if stable_asset?(asset) && account.currency == "USD"

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
      Security.find_or_create_by!(ticker: ticker.upcase) do |security|
        security.name = ticker.upcase
      end
    end

    def binance_balances
      payload = broker_connection.raw_account_payload
      payload.is_a?(Hash) ? payload.fetch("balances", []) : []
    end

    def binance_trades
      Array(broker_connection.raw_transactions_payload)
    end
end
