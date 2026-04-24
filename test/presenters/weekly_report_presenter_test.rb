require "test_helper"

class WeeklyReportPresenterTest < ActiveSupport::TestCase
  test "reads overview metrics from persisted payload" do
    user = users(:family_admin)
    period = Period.custom(start_date: Date.parse("2026-03-21"), end_date: Date.parse("2026-03-27"))
    payload = WeeklyReportBuilder.new(user: user, period: period).build

    report = user.weekly_reports.create!(
      period_start_date: period.start_date,
      period_end_date: period.end_date,
      scheduled_for: Time.current,
      status: "sent",
      sent_at: Time.current,
      payload: payload
    )

    presenter = WeeklyReportPresenter.new(report)
    overview_metrics = presenter.overview_metrics.index_by { |metric| metric[:id] }

    assert_equal payload.dig(:overview, :trading_turnover).to_d, overview_metrics["trading_turnover"][:amount]
    assert_equal payload.dig(:overview, :net_buys).to_d, overview_metrics["net_buys"][:amount]
    assert_equal payload.dig(:overview, :taxes_fees).to_d, overview_metrics["taxes_fees"][:amount]
  end
end
