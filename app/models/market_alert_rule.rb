class MarketAlertRule < ApplicationRecord
  CONDITIONS = %w[change_percent_below change_percent_above].freeze

  # Preset rules shown in the UI (US major indices)
  PRESETS = [
    { symbol: "^GSPC",  name: "S&P 500",    condition: "change_percent_below", threshold: -2.0 },
    { symbol: "^IXIC",  name: "Nasdaq",      condition: "change_percent_below", threshold: -2.0 },
    { symbol: "^DJI",   name: "Dow Jones",   condition: "change_percent_below", threshold: -2.0 }
  ].freeze

  belongs_to :user

  validates :symbol, :condition, :threshold, presence: true
  validates :condition, inclusion: { in: CONDITIONS }
  validates :symbol, uniqueness: { scope: [ :user_id, :condition ] }

  scope :enabled, -> { where(enabled: true) }

  def triggered_by?(snapshot)
    return false unless snapshot.change_percent.present?

    case condition
    when "change_percent_below"
      snapshot.change_percent <= threshold
    when "change_percent_above"
      snapshot.change_percent >= threshold
    else
      false
    end
  end

  def condition_label
    case condition
    when "change_percent_below" then "跌幅超过"
    when "change_percent_above" then "涨幅超过"
    end
  end

  def threshold_display
    pct = threshold.abs
    "#{pct.to_f.round(1)}%"
  end
end
