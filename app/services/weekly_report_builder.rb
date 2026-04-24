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
        top_securities: report.top_securities(limit: 5).map do |row|
          {
            ticker: row.ticker,
            name: row.name,
            buy_volume: row.buy_volume.to_f,
            sell_volume: row.sell_volume.to_f,
            net_flow: row.net_flow.to_f,
            trade_count: row.trade_count
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

      {
        account_count: account_sections.count,
        trading_turnover: account_sections.sum { |section| metric_amount(section, "trading_turnover") },
        net_buys: account_sections.sum { |section| metric_amount(section, "net_buys") },
        contributions: account_sections.sum { |section| metric_amount(section, "contributions") },
        income: account_sections.sum { |section| metric_amount(section, "income") },
        taxes_fees: account_sections.sum { |section| metric_amount(section, "taxes_fees") },
        most_active_account: most_active_account && {
          name: most_active_account[:name],
          turnover: metric_amount(most_active_account, "trading_turnover")
        },
        top_security: top_security
      }
    end

    def aggregate_top_security(account_sections)
      grouped = account_sections.flat_map { |section| section[:top_securities] }.group_by { |security| security[:ticker] }
      top = grouped.max_by do |_ticker, rows|
        rows.sum { |row| row[:buy_volume] + row[:sell_volume] }
      end

      return nil unless top

      ticker, rows = top
      representative = rows.first

      {
        ticker: ticker,
        name: representative[:name],
        turnover: rows.sum { |row| row[:buy_volume] + row[:sell_volume] },
        trade_count: rows.sum { |row| row[:trade_count] }
      }
    end

    def metric_amount(section, key)
      section.dig(:summary, key, :amount).to_f
    end
end
