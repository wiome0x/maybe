require "test_helper"

class Settings::WeeklyReportSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "should get show" do
    get settings_weekly_report_path

    assert_response :success
    assert_includes response.body, "weekly_report_subscription"
  end

  test "should update subscription" do
    patch settings_weekly_report_path, params: {
      weekly_report_subscription: {
        enabled: "1",
        send_weekday: "2",
        send_hour: "9",
        timezone: "Asia/Shanghai",
        period_key: "last_7_days"
      }
    }

    assert_redirected_to settings_weekly_report_path
    subscription = users(:family_admin).reload.weekly_report_subscription
    assert subscription.enabled?
    assert_equal 2, subscription.send_weekday
    assert_equal 9, subscription.send_hour
  end
end
