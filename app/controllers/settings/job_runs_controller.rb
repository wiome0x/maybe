class Settings::JobRunsController < ApplicationController
  layout "settings"
  before_action :require_admin

  def show
    scope = ScheduledJobRun.recent

    if params[:job_name].present?
      scope = scope.for_job(params[:job_name])
    end

    if params[:status].present?
      scope = scope.where(status: params[:status])
    end

    @job_names = ScheduledJobRun.distinct.pluck(:job_name).sort
    @runs = scope.limit(100)

    @stats = {
      total:     ScheduledJobRun.count,
      completed: ScheduledJobRun.completed.count,
      failed:    ScheduledJobRun.failed.count,
      last_run:  ScheduledJobRun.recent.first
    }
  end

  private

    def require_admin
      redirect_to root_path, alert: "Not authorized." unless Current.user.admin?
    end
end
