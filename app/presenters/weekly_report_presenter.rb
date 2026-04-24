class WeeklyReportPresenter
  METRIC_IDS = %w[trading_turnover net_buys contributions income taxes_fees].freeze

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
      METRIC_IDS.map do |id|
        {
          id: id,
          label: metric_label(id),
          amount: numeric_amount(payload.dig(:overview, id)),
          currency: overview_currency,
          color: metric_color(id),
          note: nil
      }
    end
  end

  def overview_breakdowns
    rows = payload.dig(:overview, :breakdowns) || []
    return rows.map { |row| row.merge(amount: numeric_amount(row[:amount])) } if rows.any?

    summary_to_breakdowns(overview_metrics)
  end

  def overview_turnover_series
    payload.dig(:overview, :turnover_series)
  end

  def overview_contribution_series
    payload.dig(:overview, :contribution_series)
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
        "contributions" => "#15803D",
        "income" => "#B45309",
        "taxes_fees" => "#B91C1C"
      }.fetch(id, "#475569")
    end

    def summary_to_breakdowns(metrics)
      metrics.filter { |metric| metric[:amount].positive? }.map do |metric|
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

    def currency
      data[:currency]
    end

    def metrics
      list = data[:metrics] || []
      list.select { |metric| METRIC_IDS.include?(metric[:id].to_s) }.map do |metric|
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
      data[:turnover_chart_data]
    end

    def contribution_series
      data[:contribution_series]
    end

    def top_securities
      (data[:top_securities] || []).map do |row|
        row.merge(
          buy_volume: numeric_amount(row[:buy_volume]),
          sell_volume: numeric_amount(row[:sell_volume]),
          net_flow: numeric_amount(row[:net_flow])
        )
      end
    end

    def max_security_turnover
      top_securities.map { |row| row[:buy_volume].to_d + row[:sell_volume].to_d }.max.to_d
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
