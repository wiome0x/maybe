require "test_helper"

class BarkNotificationDispatcherTest < ActiveSupport::TestCase
  class FakeNotifier
    cattr_accessor :deliveries, default: []

    def initialize(subscription)
      @subscription = subscription
    end

    def deliver(title:, body:, url: nil, **)
      self.class.deliveries << { subscription: @subscription, title: title, body: body, url: url }
      {}
    end
  end

  setup do
    BarkNotification.delete_all
    BarkNotificationSubscription.delete_all
    FakeNotifier.deliveries = []
  end

  test "dispatches realtime bark notifications immediately" do
    user = users(:family_admin)
    user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "abc123",
      push_categories: [ "weekly_report" ],
      delivery_frequency: "realtime",
      timezone: "Asia/Shanghai"
    )

    BarkNotificationScheduler.enqueue!(
      user: user,
      category: "weekly_report",
      title: "Weekly report ready",
      body: "Your weekly report is ready",
      target_url: "https://example.com/reports/weekly",
      source_key: "weekly_report:2026-04-25",
      occurred_at: Time.utc(2026, 4, 25, 2, 0, 0)
    )

    dispatched = BarkNotificationDispatcher.new(now: Time.utc(2026, 4, 25, 2, 5, 0), notifier_class: FakeNotifier).dispatch_due

    assert_equal 1, dispatched
    assert_equal 1, FakeNotifier.deliveries.size
    assert_equal "Weekly report ready", FakeNotifier.deliveries.first[:title]
    assert_equal "sent", BarkNotification.first.status
  end

  test "market news stays queued until daily digest time even for realtime subscriptions" do
    user = users(:family_admin)
    user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "abc123",
      push_categories: [ "market_news" ],
      delivery_frequency: "realtime",
      digest_hour: 8,
      timezone: "Asia/Shanghai"
    )

    BarkNotificationScheduler.enqueue!(
      user: user,
      category: "market_news",
      title: "Fed signals pause",
      body: "Fed officials kept rates unchanged",
      target_url: "https://example.com/fed",
      source_key: "market_news:fed-pause",
      occurred_at: Time.utc(2026, 4, 25, 2, 0, 0)
    )

    dispatched = BarkNotificationDispatcher.new(now: Time.utc(2026, 4, 25, 2, 5, 0), notifier_class: FakeNotifier).dispatch_due

    assert_equal 0, dispatched
    assert_empty FakeNotifier.deliveries
    assert_equal "pending", BarkNotification.first.status

    dispatched = BarkNotificationDispatcher.new(now: Time.utc(2026, 4, 26, 0, 0, 0), notifier_class: FakeNotifier).dispatch_due

    assert_equal 1, dispatched
    assert_equal 1, FakeNotifier.deliveries.size
    assert_equal "Market news digest (1)", FakeNotifier.deliveries.first[:title]
    assert_equal "sent", BarkNotification.first.reload.status
  end

  test "groups hourly digest notifications into one bark push" do
    user = users(:family_admin)
    user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "abc123",
      push_categories: [ "weekly_report" ],
      delivery_frequency: "hourly_digest",
      timezone: "Asia/Shanghai"
    )

    occurred_at = Time.utc(2026, 4, 25, 1, 20, 0)
    BarkNotificationScheduler.enqueue!(
      user: user,
      category: "weekly_report",
      title: "First report update",
      body: "First body",
      source_key: "weekly_report:first",
      occurred_at: occurred_at
    )
    BarkNotificationScheduler.enqueue!(
      user: user,
      category: "weekly_report",
      title: "Second report update",
      body: "Second body",
      source_key: "weekly_report:second",
      occurred_at: occurred_at + 5.minutes
    )

    dispatched = BarkNotificationDispatcher.new(now: Time.utc(2026, 4, 25, 2, 1, 0), notifier_class: FakeNotifier).dispatch_due

    assert_equal 2, dispatched
    assert_equal 1, FakeNotifier.deliveries.size
    assert_match "Weekly report updates (2)", FakeNotifier.deliveries.first[:title]
    assert_match "1. First report update", FakeNotifier.deliveries.first[:body]
    assert_match "2. Second report update", FakeNotifier.deliveries.first[:body]
  end
end
