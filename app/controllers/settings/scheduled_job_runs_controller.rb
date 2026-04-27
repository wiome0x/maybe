class Settings::ScheduledJobRunsController < ApplicationController
  layout "settings"

  before_action :ensure_admin

  def index
    # All known cron jobs from schedule.yml, including the sub-job tracked by MarketSnapshot::Importer
    job_names = %w[
      import_market_data
      import_market_snapshots
      sync_broker_connections
      clean_syncs
      import_market_news
      dispatch_bark_notifications
      run_security_health_checks
      clean_api_request_logs
      dispatch_weekly_reports
    ]

    days = (params[:days].presence_in(%w[7 30 90]) || "7").to_i
    since = days.days.ago.to_date

    runs = ScheduledJobRun.where(run_date: since..).order(run_date: :desc, job_name: :asc)

    # Latest run per job for the summary cards
    @latest_runs = job_names.index_with do |name|
      runs.find { |r| r.job_name == name }
    end

    @recent_runs = runs
    @days = days
  end

  private

    def ensure_admin
      redirect_to root_path, alert: "Not authorized" unless Current.user&.admin?
    end
end
