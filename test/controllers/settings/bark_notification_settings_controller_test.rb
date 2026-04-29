require "test_helper"

class Settings::BarkNotificationSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "should get show" do
    get settings_bark_notification_path

    assert_response :success
    assert_includes response.body, "bark_notification_subscription"
  end

  test "should update bark push subscription" do
    patch settings_bark_notification_path, params: {
      bark_notification_subscription: {
        enabled: "1",
        server_url: "https://api.day.app",
        device_key: "abc123",
        delivery_frequency: "daily_digest",
        digest_hour: "7",
        timezone: "Asia/Shanghai",
        push_categories: [ "market_news", "weekly_report" ]
      }
    }

    assert_redirected_to settings_bark_notification_path
    subscription = users(:family_admin).reload.bark_notification_subscription
    assert subscription.enabled?
    assert_equal "daily_digest", subscription.delivery_frequency
    assert_equal 7, subscription.digest_hour
    assert_equal %w[market_news weekly_report], subscription.push_categories
  end

  test "should send bark test push" do
    users(:family_admin).bark_notification_subscription&.destroy
    users(:family_admin).create_bark_notification_subscription!(
      enabled: true,
      server_url: "https://api.day.app",
      device_key: "abc123",
      push_categories: [ "market_news" ],
      timezone: "Asia/Shanghai"
    )

    BarkNotifier.any_instance.expects(:deliver).once.returns({})

    post test_settings_bark_notification_path

    assert_redirected_to settings_bark_notification_path
  end
end
