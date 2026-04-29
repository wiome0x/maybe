class MarketAlertChecker
  def initialize(date: Date.current)
    @date = date
  end

  def check
    check_market_rules
    check_watchlist_ma_rules
    check_watchlist_change_rules
  end

  private
    attr_reader :date

    def check_market_rules
      snapshots = MarketSnapshot.for_date(date).index_by { |s| s.symbol.upcase }
      return if snapshots.empty?

      MarketAlertRule.enabled.market.includes(:user).find_each do |rule|
        snapshot = snapshots[rule.symbol.upcase]
        next unless snapshot && rule.triggered_by?(snapshot)
        enqueue_notification(rule, body_for_snapshot(rule, snapshot))
      end
    end

    def check_watchlist_ma_rules
      MarketAlertRule.enabled.watchlist
                     .where.not(condition: %w[change_percent_below change_percent_above])
                     .includes(:user).find_each do |rule|
        period = rule.ma_period
        next unless period

        security = Security.find_by(ticker: rule.symbol.upcase)
        next unless security

        prices = Security::Price.where(security: security, currency: "USD")
                                .where("date <= ?", date)
                                .order(date: :desc)
                                .limit(period)
                                .pluck(:price)
        next if prices.size < period

        current_price = prices.first.to_f
        ma_value      = prices.sum.to_f / period
        next unless rule.triggered_by_ma?(current_price, ma_value)

        deviation = ((current_price - ma_value) / ma_value * 100).round(2)
        body = "#{rule.symbol} 当前价 #{current_price.round(2)}，MA#{period} = #{ma_value.round(2)}，偏离 #{deviation}%，触发预警（#{rule.condition_label} #{rule.threshold_display}）"
        enqueue_notification(rule, body)
      end
    end

    def body_for_snapshot(rule, snapshot)
      pct = snapshot.change_percent.to_f.round(2)
      direction = pct >= 0 ? "+" : ""
      "#{rule.symbol} 今日涨跌幅 #{direction}#{pct}%，触发预警（阈值 #{rule.condition_label} #{rule.threshold_display}）"
    end

    def check_watchlist_change_rules
      rules = MarketAlertRule.enabled.watchlist
                             .where(condition: %w[change_percent_below change_percent_above])
                             .includes(:user)
      return if rules.none?

      symbols = rules.map { |r| r.symbol.upcase }.uniq
      snapshots = MarketSnapshot.for_date(date).where(symbol: symbols).index_by { |s| s.symbol.upcase }
      return if snapshots.empty?

      rules.find_each do |rule|
        snapshot = snapshots[rule.symbol.upcase]
        next unless snapshot && rule.triggered_by?(snapshot)
        enqueue_notification(rule, body_for_snapshot(rule, snapshot))
      end
    end

    def enqueue_notification(rule, body)
      title = "#{rule.name.presence || rule.symbol} 异动提醒"
      BarkNotificationScheduler.enqueue!(
        user:        rule.user,
        category:    "market_alerts",
        title:       title,
        body:        body,
        source_key:  "market_alert:#{rule.id}:#{date.iso8601}:#{Time.current.to_i}",
        occurred_at: Time.current,
        payload:     { symbol: rule.symbol, condition: rule.condition, threshold: rule.threshold.to_f, date: date.iso8601 }
      )
    rescue => e
      Rails.logger.warn("[MarketAlertChecker] Failed to enqueue for rule #{rule.id}: #{e.message}")
    end
end
