#
# Builds an IBKR-like cash report from the transaction legs Plaid actually exposes.
#
# Important limitation:
# Plaid FX investment transactions (for example `USD.HKD`) only expose one currency leg.
# That means this report is exact for non-FX activity, but FX-heavy accounts cannot fully
# reconstruct IBKR's per-currency trade buy/sell lines or settled-cash lines from Plaid alone.
#
class PlaidAccount::Investments::CashReport
  CASH_RECEIPT_NAME_PATTERNS = PlaidAccount::Investments::TransactionsProcessor::CASH_INFLOW_NAME_PATTERNS
  DIVIDEND_NAME_PATTERN = /CASH DIVIDEND/i
  WITHHOLDING_TAX_PATTERN = /\bTAX\b/i

  Summary = Data.define(
    :currency,
    :opening_cash,
    :commissions,
    :deposits_withdrawals,
    :dividends,
    :trade_sells,
    :trade_buys,
    :withholding_tax,
    :ending_cash,
    :fx_translation_gain_loss
  )

  def initialize(account, start_date:, end_date:)
    @account = account
    @start_date = start_date.to_date
    @end_date = end_date.to_date
  end

  def per_currency
    currencies.index_with { |currency| summarize_currency(currency) }
  end

  def exact?
    unsupported_reasons.empty?
  end

  def unsupported_reasons
    reasons = []
    reasons << :missing_forex_counterparty_legs if contains_forex_transactions?
    reasons << :missing_settlement_dates if contains_forex_transactions?
    reasons
  end

  def base_currency_summary
    lines = {
      opening_cash: converted_opening_cash,
      commissions: converted_trade_fees,
      deposits_withdrawals: converted_cash_receipts,
      dividends: converted_dividends,
      trade_sells: converted_trade_sells,
      trade_buys: converted_trade_buys,
      withholding_tax: converted_withholding_tax
    }

    ending_cash = per_currency.values.sum do |summary|
      convert_amount(summary.ending_cash, from_currency: summary.currency, date: end_date)
    end

    subtotal = lines.values.sum
    fx_translation_gain_loss = exact? ? (ending_cash - subtotal) : nil

    Summary.new(
      currency: account.currency,
      opening_cash: lines[:opening_cash],
      commissions: lines[:commissions],
      deposits_withdrawals: lines[:deposits_withdrawals],
      dividends: lines[:dividends],
      trade_sells: lines[:trade_sells],
      trade_buys: lines[:trade_buys],
      withholding_tax: lines[:withholding_tax],
      ending_cash: ending_cash,
      fx_translation_gain_loss: fx_translation_gain_loss
    )
  end

  private
    attr_reader :account, :start_date, :end_date

    def plaid_account
      @plaid_account ||= account.plaid_account
    end

    def raw_transactions
      @raw_transactions ||= Array(plaid_account&.raw_investments_payload&.fetch("transactions", []))
    end

    def all_entries_by_plaid_id
      @all_entries_by_plaid_id ||= account.entries.where.not(plaid_id: nil).index_by(&:plaid_id)
    end

    def period_transactions
      @period_transactions ||= raw_transactions.select do |transaction|
        tx_date = parse_date(transaction["date"])
        tx_date.present? && tx_date.between?(start_date, end_date)
      end
    end

    def pre_period_transactions
      @pre_period_transactions ||= raw_transactions.select do |transaction|
        tx_date = parse_date(transaction["date"])
        tx_date.present? && tx_date < start_date
      end
    end

    def currencies
      @currencies ||= begin
        tx_currencies = (pre_period_transactions + period_transactions).map { |transaction| transaction["iso_currency_code"].presence }.compact
        tx_currencies.uniq
      end
    end

    def summarize_currency(currency)
      prior_transactions = pre_period_transactions.select { |transaction| transaction["iso_currency_code"] == currency }
      current_transactions = period_transactions.select { |transaction| transaction["iso_currency_code"] == currency }

      opening_cash = prior_transactions.sum { |transaction| report_signed_amount(transaction) }
      commissions = current_transactions.sum { |transaction| trade_fee(transaction) }
      deposits_withdrawals = current_transactions.sum { |transaction| cash_receipt?(transaction) ? report_signed_amount(transaction) : 0 }
      dividends = current_transactions.sum { |transaction| dividend?(transaction) ? report_signed_amount(transaction) : 0 }
      trade_sells = current_transactions.sum { |transaction| sell?(transaction) ? report_signed_amount(transaction) : 0 }
      trade_buys = current_transactions.sum { |transaction| buy?(transaction) ? report_signed_amount(transaction) : 0 }
      withholding_tax = current_transactions.sum { |transaction| withholding_tax?(transaction) ? report_signed_amount(transaction) : 0 }

      calculated_ending_cash = opening_cash +
        commissions +
        deposits_withdrawals +
        dividends +
        trade_sells +
        trade_buys +
        withholding_tax

      ending_cash = provider_brokerage_cash_for(currency) || calculated_ending_cash

      Summary.new(
        currency: currency,
        opening_cash: opening_cash,
        commissions: commissions,
        deposits_withdrawals: deposits_withdrawals,
        dividends: dividends,
        trade_sells: trade_sells,
        trade_buys: trade_buys,
        withholding_tax: withholding_tax,
        ending_cash: ending_cash,
        fx_translation_gain_loss: 0
      )
    end

    def converted_opening_cash
      pre_period_transactions.sum do |transaction|
        convert_transaction_amount(transaction, report_signed_amount(transaction), date: start_date.prev_day)
      end
    end

    def converted_trade_fees
      period_transactions.sum { |transaction| convert_transaction_amount(transaction, trade_fee(transaction), date: parse_date(transaction["date"])) }
    end

    def converted_cash_receipts
      period_transactions.sum do |transaction|
        cash_receipt?(transaction) ? convert_transaction_amount(transaction, report_signed_amount(transaction), date: parse_date(transaction["date"])) : 0
      end
    end

    def converted_dividends
      period_transactions.sum do |transaction|
        dividend?(transaction) ? convert_transaction_amount(transaction, report_signed_amount(transaction), date: parse_date(transaction["date"])) : 0
      end
    end

    def converted_trade_sells
      period_transactions.sum do |transaction|
        sell?(transaction) ? convert_transaction_amount(transaction, report_signed_amount(transaction), date: parse_date(transaction["date"])) : 0
      end
    end

    def converted_trade_buys
      period_transactions.sum do |transaction|
        buy?(transaction) ? convert_transaction_amount(transaction, report_signed_amount(transaction), date: parse_date(transaction["date"])) : 0
      end
    end

    def converted_withholding_tax
      period_transactions.sum do |transaction|
        withholding_tax?(transaction) ? convert_transaction_amount(transaction, report_signed_amount(transaction), date: parse_date(transaction["date"])) : 0
      end
    end

    def convert_transaction_amount(transaction, amount, date:)
      currency = transaction["iso_currency_code"].presence || account.currency
      convert_amount(amount, from_currency: currency, date: date)
    end

    def convert_amount(amount, from_currency:, date:)
      return amount.to_d if from_currency == account.currency

      Money.new(amount, from_currency).exchange_to(account.currency, date: date, fallback_rate: 1).amount
    end

    def report_signed_amount(transaction)
      entry = entry_for(transaction)
      return -entry.amount if entry.present?

      -transaction["amount"].to_d
    end

    def trade_fee(transaction)
      return 0 unless buy?(transaction) || sell?(transaction)

      transaction["fees"].to_d
    end

    def entry_for(transaction)
      all_entries_by_plaid_id[transaction["investment_transaction_id"]]
    end

    def provider_brokerage_cash_for(currency)
      return nil unless currency == account.currency
      return nil unless latest_holdings_snapshot_date == end_date

      brokerage_cash_holding&.fetch("institution_value", nil)&.to_d
    end

    def cash_receipt?(transaction)
      transaction["type"] == "cash" && CASH_RECEIPT_NAME_PATTERNS.any? { |pattern| pattern.match?(transaction["name"].to_s.strip) }
    end

    def dividend?(transaction)
      transaction["type"] == "cash" &&
        DIVIDEND_NAME_PATTERN.match?(transaction["name"].to_s) &&
        !WITHHOLDING_TAX_PATTERN.match?(transaction["name"].to_s)
    end

    def withholding_tax?(transaction)
      transaction["type"] == "cash" &&
        DIVIDEND_NAME_PATTERN.match?(transaction["name"].to_s) &&
        WITHHOLDING_TAX_PATTERN.match?(transaction["name"].to_s)
    end

    def buy?(transaction)
      transaction["type"] == "buy"
    end

    def sell?(transaction)
      transaction["type"] == "sell"
    end

    def contains_forex_transactions?
      raw_transactions.any? { |transaction| transaction["name"].to_s.match?(/\A[A-Z]{3}\.[A-Z]{3}\z/) }
    end

    def latest_holdings_snapshot_date
      @latest_holdings_snapshot_date ||= raw_holdings
        .filter_map { |holding| parse_date(holding["institution_price_as_of"]) }
        .max
    end

    def brokerage_cash_holding
      @brokerage_cash_holding ||= raw_holdings.find do |holding|
        security = raw_securities_by_id[holding["security_id"]]
        next false unless security

        security["type"] == "cash" && security["ticker_symbol"].to_s.start_with?("CUR:")
      end
    end

    def raw_holdings
      @raw_holdings ||= Array(plaid_account&.raw_investments_payload&.fetch("holdings", []))
    end

    def raw_securities_by_id
      @raw_securities_by_id ||= Array(plaid_account&.raw_investments_payload&.fetch("securities", []))
        .index_by { |security| security["security_id"] }
    end

    def parse_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.parse(value.to_s)
    end
end
