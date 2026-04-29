require "test_helper"

class Settings::ScheduledJobRunsControllerTest < ActionDispatch::IntegrationTest
  JobStub = Struct.new(:name, :human_cron, :cron, :klass, :enabled) do
    def enabled?
      enabled
    end
  end

  setup do
    sign_in users(:family_admin)
  end

  test "shows latest execution status for each scheduled job" do
    ScheduledJobRun.create!(
      job_name: "market_data_import",
      run_date: 2.days.ago.to_date,
      status: "failed",
      started_at: 2.days.ago,
      finished_at: 2.days.ago + 1.minute
    )
    ScheduledJobRun.create!(
      job_name: "weekly_report_dispatch",
      run_date: 1.day.ago.to_date,
      status: "completed",
      started_at: 1.day.ago,
      finished_at: 1.day.ago + 1.minute
    )

    jobs = [
      JobStub.new("market_data_import", nil, "0 6 * * *", "MarketDataImportJob", true),
      JobStub.new("weekly_report_dispatch", nil, "0 9 * * *", "WeeklyReportDispatchJob", false)
    ]

    Sidekiq::Cron::Job.stubs(:all).returns(jobs)

    get settings_scheduled_job_runs_path

    assert_response :success
    assert_includes response.body, "最新执行"
    assert_includes response.body, "失败"
    assert_includes response.body, "成功"
  end
end
