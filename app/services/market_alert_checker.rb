# Scans today's MarketSnapshot records against each user's MarketAlertRules
# and enqueues Bark notifications for any triggered rules.
#
# Called by ImportMarketDataJob after a successful import.
class MarketAlertChecker
  def initialize(date: Date.current)
    @date = date
  end

  def check
    snapshots = MarketSnapshot.for_date(@date).index_by { |s| s.symbol.upcase }
    return if snapshots.empty?

    MarketAlertRule.enabled.includes(:user).find_each do |rule|
      snapshot = snapshots[rule.symbol.upcase]
      next unless snapshot
      next unless rule.triggered_by?(snapshot)

      enqueue_notification(rule, snapshot)
    end
  end

  private
    attr_reader :date

    def enqueue_notification(rule, snapshot)
      pct = snapshot.change_percent.to_f.round(2)
      direction = pct >= 0 ? "+" : ""
      title = "#{rule.name.presence || rule.symbol} 大盘异动"
      body  = "#{rule.symbol} 今日涨跌幅 #{direction}#{pct}%，触发预警（阈值 #{rule.condition_label} #{rule.threshold_display}）"

      BarkNotificationScheduler.enqueue!(
        user:        rule.user,
        category:    "market_alerts",
        title:       title,
        body:        body,
        source_key:  "market_alert:#{rule.id}:#{date.iso8601}",
        occurred_at: Time.current,
        payload: {
          symbol:         rule.symbol,
          change_percent: pct,
          threshold:      rule.threshold.to_f,
          condition:      rule.condition,
          date:           date.iso8601
        }
      )
    rescue => e
      Rails.logger.warn("[MarketAlertChecker] Failed to enqueue for rule #{rule.id}: #{e.message}")
    end
end
