class WeeklyReportBuilder
  def initialize(user:, period:)
    @user = user
    @period = period
  end

  def build
    account_sections = investment_accounts.map { |account| build_account_section(account) }

    {
      generated_at: Time.current.iso8601,
      recipient_email: user.email,
      period: {
        key: period.key,
        label: period.label,
        start_date: period.start_date.iso8601,
        end_date: period.end_date.iso8601
      },
      overview: build_overview(account_sections),
      accounts: account_sections
    }
  end

  private
    attr_reader :user, :period

    def investment_accounts
      user.family.accounts.visible.where(accountable_type: "Investment").alphabetically
    end

    def build_account_section(account)
      report = Account::InvestmentReport.new(account, period: period)
      metrics = report.metrics.map do |metric|
        {
          id: metric.id.to_s,
          label: metric.label,
          amount: metric.amount.to_f,
          note: metric.note,
          color: metric.color
        }
      end

      {
        account_id: account.id,
        name: account.name,
        currency: account.currency,
        subtitle: report.subtitle,
        summary: metrics.index_by { |metric| metric[:id] }.slice("trading_turnover", "net_buys", "contributions", "income", "taxes_fees"),
        breakdowns: report.breakdowns.map do |row|
          {
            id: row.id,
            label: row.label,
            amount: row.amount.to_f,
            count: row.count,
            color: row.color,
            currency: account.currency
          }
        end,
        turnover_chart_data: report.turnover_chart_data,
        contribution_series: report.contribution_series.as_json,
        top_securities: report.top_securities(limit: 5).map do |row|
          {
            ticker: row.ticker,
            name: row.name,
            buy_volume: row.buy_volume.to_f,
            sell_volume: row.sell_volume.to_f,
            net_flow: row.net_flow.to_f,
            trade_count: row.trade_count,
            currency: account.currency
          }
        end,
        recent_activity: report.recent_activity(limit: 6).map do |row|
          {
            date: row.entry.date.iso8601,
            kind: row.kind.to_s,
            label: row.label,
            detail: row.detail,
            amount: row.amount.to_f,
            color: row.color
          }
        end,
        metrics: metrics
      }
    end

    def build_overview(account_sections)
      top_security = aggregate_top_security(account_sections)
      most_active_account = account_sections.max_by { |section| metric_amount(section, "trading_turnover") }
      family_currency = user.family.currency
      overview_breakdowns = aggregate_breakdowns(account_sections)

      {
        account_count: account_sections.count,
        currency: family_currency,
        trading_turnover: account_sections.sum { |section| converted_metric_amount(section, "trading_turnover", family_currency) },
        net_buys: account_sections.sum { |section| converted_metric_amount(section, "net_buys", family_currency) },
        contributions: account_sections.sum { |section| converted_metric_amount(section, "contributions", family_currency) },
        income: account_sections.sum { |section| converted_metric_amount(section, "income", family_currency) },
        taxes_fees: account_sections.sum { |section| converted_metric_amount(section, "taxes_fees", family_currency) },
        most_active_account: most_active_account && {
          name: most_active_account[:name],
          turnover: converted_metric_amount(most_active_account, "trading_turnover", family_currency)
        },
        top_security: top_security,
        breakdowns: overview_breakdowns,
        turnover_series: aggregate_series(account_sections, series_key: :turnover_chart_data, target_currency: family_currency),
        contribution_series: aggregate_series(account_sections, series_key: :contribution_series, target_currency: family_currency)
      }
    end

    def aggregate_top_security(account_sections)
      grouped = account_sections.flat_map { |section| section[:top_securities] }.group_by { |security| security[:ticker] }
      top = grouped.max_by do |_ticker, rows|
        rows.sum { |row| convert_amount(row[:buy_volume] + row[:sell_volume], rows.first[:currency] || rows.first["currency"], user.family.currency) }
      end

      return nil unless top

      ticker, rows = top
      representative = rows.first

      {
        ticker: ticker,
        name: representative[:name],
        turnover: rows.sum { |row| convert_amount(row[:buy_volume] + row[:sell_volume], representative[:currency] || representative["currency"] || user.family.currency, user.family.currency) },
        trade_count: rows.sum { |row| row[:trade_count] }
      }
    end

    def metric_amount(section, key)
      section.dig(:summary, key, :amount).to_f
    end

    def converted_metric_amount(section, key, target_currency)
      convert_amount(metric_amount(section, key), section[:currency], target_currency)
    end

    def convert_amount(amount, from_currency, target_currency)
      return amount.to_d if from_currency.blank? || from_currency == target_currency

      Money.new(amount, from_currency).exchange_to(target_currency, date: period.end_date, fallback_rate: 1).amount
    end

    def aggregate_breakdowns(account_sections)
      grouped = account_sections.flat_map { |section| section[:breakdowns] }.group_by { |row| row[:id] }

      grouped.map do |id, rows|
        sample = rows.first
        {
          id: id,
          label: sample[:label],
          amount: rows.sum { |row| convert_amount(row[:amount], row[:currency], user.family.currency) },
          count: rows.sum { |row| row[:count].to_i },
          color: sample[:color]
        }
      end.sort_by { |row| -row[:amount] }
    end

    def aggregate_series(account_sections, series_key:, target_currency:)
      series_values = Hash.new(0.to_d)
      value_details = {}

      account_sections.each do |section|
        series = section[series_key]
        next unless series.present?

        section_currency = section[:currency]
        values = (series[:values] || series["values"] || [])

        values.each do |value|
          date = (value[:date] || value["date"]).to_date
          raw_series_value = value[:value] || value["value"]
          raw_value =
            if raw_series_value.is_a?(Money)
              raw_series_value.amount
            elsif raw_series_value.respond_to?(:dig)
              raw_series_value.dig(:amount) || raw_series_value.dig("amount") || raw_series_value
            else
              raw_series_value || 0
            end
          converted_value = convert_amount(raw_value, section_currency, target_currency)
          series_values[date] += converted_value
          value_details[date] ||= value
        end
      end

      return nil if series_values.empty?

      aggregated_values = series_values.sort_by { |date, _value| date }.map do |date, value|
        detail = value_details[date] || {}
        {
          date: date,
          value: Money.new(value, target_currency),
          activities: detail[:activities] || detail["activities"] || [],
          activity_count: detail[:activity_count] || detail["activity_count"] || 0,
          activity_summary_label: detail[:activity_summary_label] || detail["activity_summary_label"]
        }
      end

      Series.from_raw_values(aggregated_values).as_json
    end
end
