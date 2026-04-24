class Account::InvestmentReport
  CASH_RECEIPT_NAME_PATTERNS = PlaidAccount::Investments::TransactionsProcessor::CASH_INFLOW_NAME_PATTERNS
  DIVIDEND_NAME_PATTERN = /CASH DIVIDEND/i
  WITHHOLDING_TAX_PATTERN = /\bTAX\b/i
  FOREX_NAME_PATTERN = /\A[A-Z]{3}\.[A-Z]{3}\z/

  Metric = Data.define(:id, :label, :amount, :note, :color)
  Breakdown = Data.define(:id, :label, :amount, :count, :color)
  SecuritySummary = Data.define(:ticker, :name, :buy_volume, :sell_volume, :net_flow, :trade_count)
  ActivityRow = Data.define(:entry, :kind, :label, :detail, :amount, :color)

  attr_reader :account, :period

  def initialize(account, period:)
    @account = account
    @period = period
  end

  def title
    I18n.t("investments.reports.title", period: period.label)
  end

  def subtitle
    "#{I18n.l(period.start_date, format: :long)} - #{I18n.l(period.end_date, format: :long)}"
  end

  def cash_report
    @cash_report ||= if account.linked? && account.plaid_account&.raw_investments_payload.present?
      PlaidAccount::Investments::CashReport.new(account, start_date: period.start_date, end_date: period.end_date)
    end
  end

  def exact_report?
    cash_report&.exact? || false
  end

  def coverage_warnings
    return [] unless cash_report

    cash_report.unsupported_reasons.map do |reason|
      case reason
      when :missing_forex_counterparty_legs
        I18n.t("investments.reports.coverage_warnings.missing_forex_counterparty_legs")
      when :missing_settlement_dates
        I18n.t("investments.reports.coverage_warnings.missing_settlement_dates")
      end
    end.compact
  end

  def metrics
    @metrics ||= [
      Metric.new(
        id: :trading_turnover,
        label: I18n.t("investments.reports.metrics.trading_turnover.label"),
        amount: buys_total + sells_total,
        note: I18n.t("investments.reports.metrics.trading_turnover.note", count: trade_entries.count),
        color: "#0F766E"
      ),
      Metric.new(
        id: :net_buys,
        label: I18n.t("investments.reports.metrics.net_buys.label"),
        amount: buys_total - sells_total,
        note: I18n.t("investments.reports.metrics.net_buys.note", buys: buy_trade_count, sells: sell_trade_count),
        color: "#1D4ED8"
      ),
      Metric.new(
        id: :contributions,
        label: I18n.t("investments.reports.metrics.contributions.label"),
        amount: deposits_total,
        note: I18n.t("investments.reports.metrics.contributions.note", count: deposit_entries.count),
        color: "#15803D"
      ),
      Metric.new(
        id: :income,
        label: I18n.t("investments.reports.metrics.income.label"),
        amount: dividends_total,
        note: I18n.t("investments.reports.metrics.income.note", count: dividend_entries.count),
        color: "#B45309"
      ),
      Metric.new(
        id: :taxes_fees,
        label: I18n.t("investments.reports.metrics.taxes_fees.label"),
        amount: withholding_total + fees_total,
        note: I18n.t("investments.reports.metrics.taxes_fees.note"),
        color: "#B91C1C"
      ),
      Metric.new(
        id: :fx_volume,
        label: I18n.t("investments.reports.metrics.fx_volume.label"),
        amount: forex_total,
        note: I18n.t("investments.reports.metrics.fx_volume.note", count: forex_entries.count),
        color: "#475569"
      )
    ]
  end

  def breakdowns
    @breakdowns ||= [
      Breakdown.new("buys", I18n.t("investments.reports.breakdowns.buys"), buys_total, buy_trade_count, "#1D4ED8"),
      Breakdown.new("sells", I18n.t("investments.reports.breakdowns.sells"), sells_total, sell_trade_count, "#0F766E"),
      Breakdown.new("deposits", I18n.t("investments.reports.breakdowns.deposits"), deposits_total, deposit_entries.count, "#15803D"),
      Breakdown.new("dividends", I18n.t("investments.reports.breakdowns.dividends"), dividends_total, dividend_entries.count, "#B45309"),
      Breakdown.new("taxes", I18n.t("investments.reports.breakdowns.taxes"), withholding_total + fees_total, withholding_entries.count, "#B91C1C"),
      Breakdown.new("fx", I18n.t("investments.reports.breakdowns.fx"), forex_total, forex_entries.count, "#64748B")
    ].select { |item| item.amount.positive? }
  end

  def turnover_series
    @turnover_series ||= build_series do |date|
      daily_trade_entries(date).sum { |entry| entry.amount.to_d.abs }
    end
  end

  def contribution_series
    @contribution_series ||= begin
      running_total = 0.to_d

      build_series do |date|
        running_total += deposit_entries_for(date).sum { |entry| -entry.amount.to_d }
        running_total += dividend_entries_for(date).sum { |entry| -entry.amount.to_d }
        running_total -= withholding_entries_for(date).sum(&:amount)
        running_total
      end
    end
  end

  def cash_series
    @cash_series ||= account.balance_series(period: period, view: :cash_balance)
  end

  def holdings_series
    @holdings_series ||= account.balance_series(period: period, view: :holdings_balance)
  end

  def top_securities(limit: 6)
    grouped = trade_entries.group_by { |entry| entry.trade.security.ticker }

    grouped.map do |ticker, entries|
      buy_volume = entries.select { |entry| entry.trade.qty.positive? }.sum(&:amount).to_d
      sell_volume = entries.select { |entry| entry.trade.qty.negative? }.sum { |entry| entry.amount.to_d.abs }
      SecuritySummary.new(
        ticker: ticker,
        name: entries.first.trade.security.name || ticker,
        buy_volume: buy_volume,
        sell_volume: sell_volume,
        net_flow: sell_volume - buy_volume,
        trade_count: entries.count
      )
    end.sort_by { |row| -(row.buy_volume + row.sell_volume) }.first(limit)
  end

  def max_security_turnover
    top_securities.map { |row| row.buy_volume + row.sell_volume }.max.to_d
  end

  def recent_activity(limit: 12)
    activity_entries
      .sort_by { |entry| [ entry.date, entry.created_at || Time.at(0) ] }
      .reverse
      .first(limit)
      .map do |entry|
        ActivityRow.new(
          entry: entry,
          kind: activity_kind(entry),
          label: activity_label(entry),
          detail: activity_detail(entry),
          amount: signed_display_amount(entry),
          color: activity_color(entry)
        )
      end
  end

  private
    def entries
      @entries ||= account.entries
        .includes(entryable: :security)
        .where(date: period.date_range)
        .where.not(entryable_type: "Valuation")
        .to_a
    end

    def activity_entries
      entries
    end

    def trade_entries
      @trade_entries ||= entries.select(&:trade?)
    end

    def transaction_entries
      @transaction_entries ||= entries.select(&:transaction?)
    end

    def buys_total
      trade_entries.select { |entry| entry.trade.qty.positive? }.sum(&:amount).to_d
    end

    def sells_total
      trade_entries.select { |entry| entry.trade.qty.negative? }.sum { |entry| entry.amount.to_d.abs }
    end

    def buy_trade_count
      @buy_trade_count ||= trade_entries.count { |entry| entry.trade.qty.positive? }
    end

    def sell_trade_count
      @sell_trade_count ||= trade_entries.count { |entry| entry.trade.qty.negative? }
    end

    def deposit_entries
      @deposit_entries ||= transaction_entries.select { |entry| deposit_entry?(entry) }
    end

    def dividend_entries
      @dividend_entries ||= transaction_entries.select { |entry| dividend_entry?(entry) }
    end

    def withholding_entries
      @withholding_entries ||= transaction_entries.select { |entry| withholding_entry?(entry) }
    end

    def forex_entries
      @forex_entries ||= transaction_entries.select { |entry| forex_entry?(entry) }
    end

    def deposits_total
      deposit_entries.sum { |entry| -entry.amount.to_d }
    end

    def dividends_total
      dividend_entries.sum { |entry| -entry.amount.to_d }
    end

    def withholding_total
      withholding_entries.sum(&:amount).to_d
    end

    def forex_total
      forex_entries.sum { |entry| entry.amount.to_d.abs }
    end

    def fees_total
      @fees_total ||= if cash_report
        cash_report.per_currency.values.sum do |summary|
          convert_to_account_currency(summary.commissions.abs, summary.currency, period.end_date)
        end
      else
        0.to_d
      end
    end

    def daily_trade_entries(date)
      trade_entries.select { |entry| entry.date == date }
    end

    def deposit_entries_for(date)
      deposit_entries.select { |entry| entry.date == date }
    end

    def dividend_entries_for(date)
      dividend_entries.select { |entry| entry.date == date }
    end

    def withholding_entries_for(date)
      withholding_entries.select { |entry| entry.date == date }
    end

    def build_series
      values = period.date_range.map do |date|
        {
          date: date,
          value: Money.new(yield(date), account.currency)
        }
      end

      Series.from_raw_values(values)
    end

    def convert_to_account_currency(amount, from_currency, date)
      return amount.to_d if from_currency == account.currency

      Money.new(amount, from_currency).exchange_to(account.currency, date: date, fallback_rate: 1).amount
    end

    def deposit_entry?(entry)
      entry.transaction? &&
        entry.amount.negative? &&
        CASH_RECEIPT_NAME_PATTERNS.any? { |pattern| pattern.match?(entry.name.to_s.strip) }
    end

    def dividend_entry?(entry)
      entry.transaction? &&
        entry.amount.negative? &&
        DIVIDEND_NAME_PATTERN.match?(entry.name.to_s) &&
        !WITHHOLDING_TAX_PATTERN.match?(entry.name.to_s)
    end

    def withholding_entry?(entry)
      entry.transaction? &&
        entry.amount.positive? &&
        DIVIDEND_NAME_PATTERN.match?(entry.name.to_s) &&
        WITHHOLDING_TAX_PATTERN.match?(entry.name.to_s)
    end

    def forex_entry?(entry)
      entry.transaction? &&
        entry.transaction.funds_movement? &&
        FOREX_NAME_PATTERN.match?(entry.name.to_s)
    end

    def activity_kind(entry)
      return :buy if entry.trade? && entry.trade.qty.positive?
      return :sell if entry.trade? && entry.trade.qty.negative?
      return :deposit if deposit_entry?(entry)
      return :dividend if dividend_entry?(entry)
      return :tax if withholding_entry?(entry)
      return :fx if forex_entry?(entry)

      :cash
    end

    def activity_label(entry)
      case activity_kind(entry)
      when :buy then I18n.t("investments.reports.activity.buy", ticker: entry.trade.security.ticker)
      when :sell then I18n.t("investments.reports.activity.sell", ticker: entry.trade.security.ticker)
      when :deposit then I18n.t("investments.reports.activity.deposit")
      when :dividend then I18n.t("investments.reports.activity.dividend")
      when :tax then I18n.t("investments.reports.activity.tax")
      when :fx then I18n.t("investments.reports.activity.fx")
      else entry.name
      end
    end

    def activity_detail(entry)
      if entry.trade?
        I18n.t(
          "investments.reports.activity.trade_detail",
          qty: entry.trade.qty.abs.to_s("F").sub(/\.?0+\z/, ""),
          price: entry.trade.price_money.format
        )
      else
        entry.name
      end
    end

    def signed_display_amount(entry)
      if entry.trade?
        entry.trade.qty.positive? ? -entry.amount.to_d : entry.amount.to_d.abs
      elsif deposit_entry?(entry) || dividend_entry?(entry)
        -entry.amount.to_d.abs
      else
        entry.amount.to_d
      end
    end

    def activity_color(entry)
      case activity_kind(entry)
      when :buy then "#1D4ED8"
      when :sell then "#0F766E"
      when :deposit then "#15803D"
      when :dividend then "#B45309"
      when :tax then "#B91C1C"
      when :fx then "#64748B"
      else "#475569"
      end
    end
end
