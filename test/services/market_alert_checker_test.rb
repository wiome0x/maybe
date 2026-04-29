require "test_helper"

class MarketAlertCheckerTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @date = Date.new(2026, 4, 28)
    BarkNotification.delete_all
    BarkNotificationSubscription.delete_all
    MarketAlertRule.delete_all

    @user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "testdevicekey",
      push_categories: %w[market_alerts],
      delivery_frequency: "realtime",
      timezone: "Etc/UTC"
    )
  end

  test "triggers market rule when index drops below threshold" do
    MarketSnapshot.create!(symbol: "^GSPC", name: "S&P 500", date: @date, item_type: "stock", change_percent: -2.5)

    @user.market_alert_rules.create!(
      symbol: "^GSPC", name: "S&P 500", condition: "change_percent_below",
      threshold: -2.0, rule_type: "market", enabled: true
    )

    assert_difference -> { BarkNotification.count }, 1 do
      MarketAlertChecker.new(date: @date).check
    end

    notification = BarkNotification.last
    assert_equal "market_alerts", notification.category
    assert_match "S&P 500", notification.title
    assert_match "-2.5%", notification.body
  end

  test "does not trigger market rule when change is within threshold" do
    MarketSnapshot.create!(symbol: "^GSPC", date: @date, item_type: "stock", change_percent: -1.5)

    @user.market_alert_rules.create!(
      symbol: "^GSPC", condition: "change_percent_below",
      threshold: -2.0, rule_type: "market", enabled: true
    )

    assert_no_difference -> { BarkNotification.count } do
      MarketAlertChecker.new(date: @date).check
    end
  end

  # Use MSFT (no price fixtures) to avoid conflicts with AAPL fixture prices
  test "triggers watchlist MA rule when price deviates below MA threshold" do
    security = securities(:msft)

    # current=140, MA5=(140+150+150+150+150)/5=148, deviation ≈ -5.4% < -3.0%
    [ 140.0, 150.0, 150.0, 150.0, 150.0 ].each_with_index do |price, i|
      Security::Price.create!(security: security, date: @date - i.days, price: price, currency: "USD")
    end

    @user.market_alert_rules.create!(
      symbol: "MSFT", name: "Microsoft", condition: "ma5_deviation_below",
      threshold: -3.0, rule_type: "watchlist", enabled: true
    )

    assert_difference -> { BarkNotification.count }, 1 do
      MarketAlertChecker.new(date: @date).check
    end

    notification = BarkNotification.last
    assert_equal "market_alerts", notification.category
    assert_match "MSFT", notification.body
    assert_match "MA5", notification.body
  end

  test "does not trigger watchlist MA rule when insufficient price data" do
    security = securities(:msft)
    Security::Price.create!(security: security, date: @date, price: 150.0, currency: "USD")

    @user.market_alert_rules.create!(
      symbol: "MSFT", condition: "ma5_deviation_below",
      threshold: -3.0, rule_type: "watchlist", enabled: true
    )

    assert_no_difference -> { BarkNotification.count } do
      MarketAlertChecker.new(date: @date).check
    end
  end

  test "triggers watchlist change rule when stock drops below threshold" do
    MarketSnapshot.create!(symbol: "TSLA", name: "Tesla", date: @date, item_type: "stock", change_percent: -5.5)

    @user.market_alert_rules.create!(
      symbol: "TSLA", name: "Tesla", condition: "change_percent_below",
      threshold: -5.0, rule_type: "watchlist", enabled: true
    )

    assert_difference -> { BarkNotification.count }, 1 do
      MarketAlertChecker.new(date: @date).check
    end

    notification = BarkNotification.last
    assert_equal "market_alerts", notification.category
    assert_match "Tesla", notification.title
    assert_match "-5.5%", notification.body
  end

  test "triggers watchlist change rule when stock rises above threshold" do
    MarketSnapshot.create!(symbol: "NVDA", date: @date, item_type: "stock", change_percent: 8.0)

    @user.market_alert_rules.create!(
      symbol: "NVDA", condition: "change_percent_above",
      threshold: 5.0, rule_type: "watchlist", enabled: true
    )

    assert_difference -> { BarkNotification.count }, 1 do
      MarketAlertChecker.new(date: @date).check
    end
  end

  test "does not trigger disabled rules" do
    MarketSnapshot.create!(symbol: "^GSPC", date: @date, item_type: "stock", change_percent: -3.0)

    @user.market_alert_rules.create!(
      symbol: "^GSPC", condition: "change_percent_below",
      threshold: -2.0, rule_type: "market", enabled: false
    )

    assert_no_difference -> { BarkNotification.count } do
      MarketAlertChecker.new(date: @date).check
    end
  end

  test "handles missing snapshot data gracefully" do
    @user.market_alert_rules.create!(
      symbol: "^GSPC", condition: "change_percent_below",
      threshold: -2.0, rule_type: "market", enabled: true
    )

    assert_nothing_raised do
      MarketAlertChecker.new(date: @date).check
    end
  end
end
