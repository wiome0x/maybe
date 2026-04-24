class WeeklyReportPresenter
  METRIC_IDS = %w[trading_turnover net_buys income taxes_fees].freeze

  def initialize(weekly_report)
    @weekly_report = weekly_report
    @payload = weekly_report.payload.deep_symbolize_keys
  end

  attr_reader :weekly_report

  def title
    I18n.t("settings.weekly_reports.shared.title")
  end

  def subtitle
    "#{I18n.l(weekly_report.period_start_date, format: :long)} - #{I18n.l(weekly_report.period_end_date, format: :long)}"
  end

  def recipient_email
    payload[:recipient_email].presence || weekly_report.recipient_email
  end

  def generated_at
    raw = payload[:generated_at]
    raw.present? ? Time.zone.parse(raw) : weekly_report.created_at
  rescue
    weekly_report.created_at
  end

  def overview_currency
    payload.dig(:overview, :currency).presence || weekly_report.user.family.currency
  end

  def overview_metrics
    [
      {
        id: "account_count",
        label: I18n.t("settings.weekly_reports.shared.account_count"),
        amount: payload.dig(:overview, :account_count).to_i,
        currency: nil,
        color: "#475569",
        note: nil,
        numeric: false
      },
      {
        id: "current_value",
        label: I18n.t("settings.weekly_reports.shared.current_value"),
        amount: numeric_amount(payload.dig(:overview, :current_value)),
        currency: overview_currency,
        color: "#0F766E",
        note: nil,
        numeric: true
      }
    ] + METRIC_IDS.map do |id|
      {
        id: id,
        label: metric_label(id),
        amount: numeric_amount(payload.dig(:overview, id.to_sym)),
        currency: overview_currency,
        color: metric_color(id),
        note: nil,
        numeric: true
      }
    end
  end

  def overview_breakdowns
    rows = payload.dig(:overview, :account_value_breakdown) || []
    return rows.map { |row| row.merge(amount: numeric_amount(row[:amount])) } if rows.any?

    summary_to_breakdowns(overview_metrics)
  end

  def overview_turnover_series
    payload.dig(:overview, :balance_series)
  end

  def overview_multi_balance_series
    payload.dig(:overview, :multi_balance_series)
  end

  def use_multi_account_balance_chart?
    accounts.size > 1 && overview_multi_balance_series.present?
  end

  def accounts
    (payload[:accounts] || []).map { |section| AccountSection.new(section) }
  end

  def payload
    @payload
  end

  private
  def metric_label(id)
    I18n.t("investments.reports.metrics.#{id}.label")
  end

  def metric_color(id)
    {
      "trading_turnover" => "#0F766E",
      "net_buys" => "#1D4ED8",
      "income" => "#B45309",
      "taxes_fees" => "#B91C1C"
    }.fetch(id, "#475569")
  end

  def summary_to_breakdowns(metrics)
    metrics.filter { |metric| metric[:numeric] != false && metric[:amount].positive? }.map do |metric|
      {
        id: metric[:id],
        label: metric[:label],
        amount: numeric_amount(metric[:amount]),
        color: metric[:color],
        count: nil
      }
    end
  end

  def numeric_amount(value)
    if value.is_a?(Money)
      value.amount
    elsif value.respond_to?(:dig)
      (value.dig(:amount) || value.dig("amount") || value).to_d
    else
      value.to_d
    end
  end

  class AccountSection
    def initialize(data)
      @data = data.deep_symbolize_keys
    end

    attr_reader :data

    def id
      data[:account_id]
    end

    def name
      data[:name]
    end

    def subtitle
      data[:subtitle]
    end

    def account_label
      label = data[:account_label]
      return nil if label.blank? || label == name

      label
    end

    def currency
      data[:currency]
    end

    def color
      data[:chart_color]
    end

    def current_value
      numeric_amount(data[:current_value])
    end

    def metrics
      [
        {
          id: "current_value",
          label: I18n.t("settings.weekly_reports.shared.current_value"),
          amount: current_value,
          color: color || "#0F766E",
          note: nil
        }
      ] + (data[:metrics] || []).select { |metric| METRIC_IDS.include?(metric[:id].to_s) }.map do |metric|
        metric.merge(amount: numeric_amount(metric[:amount]))
      end
    end

    def breakdowns
      rows = data[:breakdowns] || []
      return rows.map { |row| row.merge(amount: numeric_amount(row[:amount])) } if rows.any?

      metrics.filter { |metric| metric[:amount].to_d.positive? }.map do |metric|
        {
          id: metric[:id],
          label: metric[:label],
          amount: metric[:amount].to_d,
          color: metric[:color],
          count: nil
        }
      end
    end

    def turnover_chart_data
      data[:balance_chart_data].presence || data[:turnover_chart_data]
    end

    def top_holdings
      (data[:top_holdings] || []).map do |row|
        row.merge(
          amount: numeric_amount(row[:amount]),
          weight: row[:weight].to_d
        )
      end
    end

    def max_holding_amount
      top_holdings.map { |row| row[:amount].to_d }.max.to_d
    end

    def recent_activity
      (data[:recent_activity] || []).map do |row|
        row.merge(amount: numeric_amount(row[:amount]))
      end
    end

    private
    def numeric_amount(value)
      if value.is_a?(Money)
        value.amount
      elsif value.respond_to?(:dig)
        (value.dig(:amount) || value.dig("amount") || value).to_d
      else
        value.to_d
      end
    end
  end
end
