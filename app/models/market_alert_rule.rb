class MarketAlertRule < ApplicationRecord
  RULE_TYPES = %w[market watchlist].freeze

  CONDITIONS = %w[
    change_percent_below change_percent_above
    ma5_deviation_below ma5_deviation_above
    ma10_deviation_below ma10_deviation_above
    ma20_deviation_below ma20_deviation_above
    ma60_deviation_below ma60_deviation_above
  ].freeze

  MA_PERIODS = { "ma5" => 5, "ma10" => 10, "ma20" => 20, "ma60" => 60 }.freeze

  PRESETS = [
    { symbol: "^GSPC", name: "S&P 500",   condition: "change_percent_below", threshold: -2.0 },
    { symbol: "^IXIC", name: "Nasdaq",    condition: "change_percent_below", threshold: -2.0 },
    { symbol: "^DJI",  name: "Dow Jones", condition: "change_percent_below", threshold: -2.0 }
  ].freeze

  belongs_to :user

  validates :symbol, :condition, :threshold, :rule_type, presence: true
  validates :condition, inclusion: { in: CONDITIONS }
  validates :rule_type, inclusion: { in: RULE_TYPES }
  validates :symbol, uniqueness: { scope: [ :user_id, :condition ] }

  scope :enabled,   -> { where(enabled: true) }
  scope :market,    -> { where(rule_type: "market") }
  scope :watchlist, -> { where(rule_type: "watchlist") }

  def ma_condition?
    condition.start_with?("ma")
  end

  def ma_period
    MA_PERIODS.find { |prefix, _| condition.start_with?(prefix) }&.last
  end

  def triggered_by?(snapshot)
    return false unless snapshot&.change_percent.present?
    case condition
    when "change_percent_below" then snapshot.change_percent <= threshold
    when "change_percent_above" then snapshot.change_percent >= threshold
    else false
    end
  end

  def triggered_by_ma?(current_price, ma_value)
    return false if ma_value.nil? || ma_value.zero?
    deviation = (current_price - ma_value) / ma_value * 100
    case condition
    when /ma\d+_deviation_below/ then deviation <= threshold
    when /ma\d+_deviation_above/ then deviation >= threshold
    else false
    end
  end

  def condition_label
    case condition
    when "change_percent_below" then "跌幅超过"
    when "change_percent_above" then "涨幅超过"
    when /ma(\d+)_deviation_below/ then "偏离MA#{$1}低于"
    when /ma(\d+)_deviation_above/ then "偏离MA#{$1}高于"
    end
  end

  def threshold_display
    "#{threshold.to_f.round(1)}%"
  end
end
