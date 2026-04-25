require "test_helper"

class BarkNotificationSubscriptionTest < ActiveSupport::TestCase
  test "applies defaults and normalizes fields" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      server_url: "https://api.day.app/ ",
      device_key: " abc123 ",
      push_categories: [ "", "market_news", "weekly_report", "market_news" ]
    )

    assert subscription.valid?
    assert_equal "https://api.day.app", subscription.server_url
    assert_equal "abc123", subscription.device_key
    assert_equal %w[market_news weekly_report], subscription.push_categories
    assert_equal "realtime", subscription.delivery_frequency
  end

  test "extracts server url and device key from full bark url" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      device_key: "https://api.day.app/CcDjXAdfvXVeUhDMCFK4E3/%E6%B5%8B%E8%AF%95%E6%B6%88%E6%81%AF"
    )

    assert subscription.valid?
    assert_equal "https://api.day.app", subscription.server_url
    assert_equal "CcDjXAdfvXVeUhDMCFK4E3", subscription.device_key
  end

  test "calculates next daily digest time in user timezone" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      timezone: "Asia/Shanghai",
      delivery_frequency: "daily_digest",
      digest_hour: 8
    )

    occurred_at = Time.utc(2026, 4, 25, 1, 30, 0)

    assert_equal Time.utc(2026, 4, 26, 0, 0, 0), subscription.scheduled_for(occurred_at: occurred_at)
  end

  test "forces market news into daily digest scheduling" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      timezone: "Asia/Shanghai",
      delivery_frequency: "realtime",
      digest_hour: 8
    )

    occurred_at = Time.utc(2026, 4, 25, 1, 30, 0)

    assert_equal "daily_digest", subscription.delivery_frequency_for("market_news")
    assert_equal Time.utc(2026, 4, 26, 0, 0, 0), subscription.scheduled_for_category(category: "market_news", occurred_at: occurred_at)
    assert_equal "realtime", subscription.delivery_frequency_for("weekly_report")
  end
end
