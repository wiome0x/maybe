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
     update_account_balance
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
end
