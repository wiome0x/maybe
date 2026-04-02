class Settings::ApiAuditsController < ApplicationController
  layout "settings"
  before_action :require_admin

  def show
    @period_days = parse_period
    @start_date = @period_days.days.ago.to_date
    @end_date = Date.current

    @stats = ApiRequestLog.overview_stats(start_date: @start_date, end_date: @end_date)
    @daily_totals = ApiRequestLog.daily_totals(start_date: @start_date, end_date: @end_date)
    @provider_summary = ApiRequestLog.provider_summary(start_date: @start_date, end_date: @end_date)

    logs_scope = ApiRequestLog.in_period(@start_date, @end_date)
                              .by_provider(params[:provider])
                              .recent
    @pagy, @logs = pagy(logs_scope, limit: 50)
  end

  private

  def require_admin
    redirect_to root_path, alert: "Not authorized." unless Current.user.admin?
  end

  def parse_period
    case params[:period]
    when "7d" then 7
    when "90d" then 90
    else 30
    end
  end
end
