class Settings::ScheduledJobRunsController < ApplicationController
  layout "settings"

  before_action :require_admin

  def show
    @jobs = Sidekiq::Cron::Job.all.sort_by(&:name)
    @job_names = ScheduledJobRun.distinct.order(:job_name).pluck(:job_name)

    @selected_job = params[:job_name].presence
    @days         = params[:days].presence
    @start_date   = parse_date(params[:start_date])
    @end_date     = parse_date(params[:end_date])

    if @selected_job
      start_date, end_date = resolve_date_range
      @runs = ScheduledJobRun.for_job(@selected_job)
                             .in_date_range(start_date, end_date)
                             .recent
    end
  end

  private

    def require_admin
      redirect_to root_path, alert: t("not_authorized") unless Current.user.admin?
    end

    def resolve_date_range
      if @start_date && @end_date
        [ @start_date, @end_date ]
      else
        days = @days.to_i.positive? ? @days.to_i : 7
        [ days.days.ago.to_date, Date.current ]
      end
    end

    def parse_date(value)
      Date.parse(value) rescue nil
    end
end
