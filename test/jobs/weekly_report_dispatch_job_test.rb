require "test_helper"

class WeeklyReportDispatchJobTest < ActiveJob::TestCase
  setup do
    @user = users(:family_admin)
    BarkNotification.delete_all
    BarkNotificationSubscription.delete_all
    @subscription = weekly_report_subscriptions(:family_admin)
    @subscription.update!(
      enabled: true,
      send_weekday: 1,
      send_hour: 8,
      timezone: "America/New_York",
      period_key: "last_7_days"
    )
    ActionMailer::Base.deliveries.clear
  end

  test "sends due weekly report once" do
    reference_time = Time.find_zone!("America/New_York").local(2026, 4, 20, 8, 0, 0)

    assert_difference -> { WeeklyReport.count }, 1 do
      assert_difference -> { ActionMailer::Base.deliveries.size }, 1 do
        WeeklyReportDispatchJob.perform_now(reference_time: reference_time)
      end
    end

    report = WeeklyReport.order(:created_at).last
    assert_equal "sent", report.status
    assert_equal @user.email, report.recipient_email
  end

  test "does not resend existing report for same period" do
    reference_time = Time.find_zone!("America/New_York").local(2026, 4, 20, 8, 0, 0)
    period = @subscription.period_for(reference_time: reference_time)
    @user.weekly_reports.create!(
      period_start_date: period.start_date,
      period_end_date: period.end_date,
      scheduled_for: reference_time,
      status: "sent",
      sent_at: reference_time
    )

    assert_no_difference -> { WeeklyReport.count } do
      assert_no_difference -> { ActionMailer::Base.deliveries.size } do
        WeeklyReportDispatchJob.perform_now(reference_time: reference_time)
      end
    end
  end

  test "marks missing recipient as skipped" do
    @user.update!(email: "weekly@example.com")
    @user.update_column(:email, nil)
    reference_time = Time.find_zone!("America/New_York").local(2026, 4, 20, 8, 0, 0)

    assert_difference -> { WeeklyReport.count }, 1 do
      WeeklyReportDispatchJob.perform_now(reference_time: reference_time)
    end

    assert_equal "skipped", WeeklyReport.order(:created_at).last.status
  end

  test "queues bark notification when weekly report is sent" do
    @user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "abc123",
      push_categories: [ "weekly_report" ],
      delivery_frequency: "realtime",
      timezone: "America/New_York"
    )
    reference_time = Time.find_zone!("America/New_York").local(2026, 4, 20, 8, 0, 0)

    assert_difference -> { BarkNotification.count }, 1 do
      WeeklyReportDispatchJob.perform_now(reference_time: reference_time)
    end

    notification = BarkNotification.order(:created_at).last
    assert_equal "weekly_report", notification.category
    assert_match "Weekly report ready", notification.title
    assert_equal "https://example.com/settings/weekly_reports/#{WeeklyReport.order(:created_at).last.id}", notification.target_url
  end
end
