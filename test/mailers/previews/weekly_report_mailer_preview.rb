# Preview all emails at http://localhost:3000/rails/mailers/weekly_report_mailer
class WeeklyReportMailerPreview < ActionMailer::Preview
  def weekly_report
    user = User.first || raise("Create a user before previewing weekly reports")
    report = user.weekly_reports.new(
      period_start_date: 6.days.ago.to_date,
      period_end_date: Date.current,
      scheduled_for: Time.current,
      status: "sent",
      payload: WeeklyReportBuilder.new(user: user, period: Period.custom(start_date: 6.days.ago.to_date, end_date: Date.current)).build
    )

    WeeklyReportMailer.with(weekly_report: report).weekly_report
  end
end
