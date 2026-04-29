class Settings::MarketAlertsController < ApplicationController
  layout "settings"

  def show
    @market_rules    = Current.user.market_alert_rules.market.order(:symbol)
    @watchlist_rules = Current.user.market_alert_rules.watchlist.order(:symbol)
    @watchlist_items = Current.family.watchlist_items.stocks.ordered
    @presets         = MarketAlertRule::PRESETS
    @recent_alerts   = Current.user.bark_notifications
                               .where(category: "market_alerts")
                               .order(created_at: :desc)
                               .limit(20)
  end
end
