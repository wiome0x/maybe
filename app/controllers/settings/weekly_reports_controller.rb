class Settings::WeeklyReportsController < ApplicationController
  layout "settings"

  def index
    @weekly_reports = Current.user.weekly_reports.ordered.limit(50)
  end

  def show
    @weekly_report = Current.user.weekly_reports.find(params[:id])
    @report_presenter = ::WeeklyReportPresenter.new(@weekly_report)
  end
end
