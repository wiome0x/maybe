require "test_helper"

class WeeklyReportMailerTest < ActionMailer::TestCase
  test "weekly_report" do
    user = users(:family_admin)
    period = Period.custom(start_date: 13.days.ago.to_date, end_date: 7.days.ago.to_date)
    report = user.weekly_reports.create!(
      period_start_date: period.start_date,
      period_end_date: period.end_date,
      scheduled_for: Time.current,
      status: "pending",
      payload: WeeklyReportBuilder.new(user: user, period: period).build
    )

    mail = WeeklyReportMailer.with(weekly_report: report).weekly_report

    assert_equal [ user.email ], mail.to
    assert_includes mail.subject, I18n.l(period.end_date, format: :long)
    assert_match "Overall summary", mail.text_part.body.to_s
  end
end
