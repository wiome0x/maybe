class Settings::ScheduledJobRunsController < ApplicationController
  layout "settings"

  before_action :require_admin

  def show
    @jobs = Sidekiq::Cron::Job.all.sort_by(&:name)
  end

  private
    def require_admin
      redirect_to root_path, alert: "Not authorized." unless Current.user.admin?
    end
end
