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

  test "calculates next daily digest time in user timezone" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      timezone: "Asia/Shanghai",
      delivery_frequency: "daily_digest",
      digest_hour: 8
    )

    occurred_at = Time.utc(2026, 4, 25, 1, 30, 0)

    assert_equal Time.utc(2026, 4, 26, 0, 0, 0), subscription.scheduled_for(occurred_at: occurred_at)
  end
end
