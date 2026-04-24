require "test_helper"

class Settings::WeeklyReportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    sign_in @user
    @report = @user.weekly_reports.create!(
      period_start_date: 13.days.ago.to_date,
      period_end_date: 7.days.ago.to_date,
      scheduled_for: Time.current,
      status: "sent",
      sent_at: Time.current,
      payload: WeeklyReportBuilder.new(user: @user, period: Period.last_7_days).build
    )
  end

  test "should get index" do
    get settings_weekly_report_deliveries_path

    assert_response :success
    assert_includes response.body, settings_weekly_report_delivery_path(@report)
  end

  test "should get show" do
    get settings_weekly_report_delivery_path(@report)

    assert_response :success
    assert_includes response.body, @report.recipient_email
  end
end
