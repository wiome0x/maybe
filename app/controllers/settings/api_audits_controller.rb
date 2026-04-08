class Settings::ApiAuditsController < ApplicationController
  layout "settings"
  before_action :require_admin

  def show
    @audit_mode = params[:audit_mode] == "plaid" ? "plaid" : "api"
    @period_days = parse_period
    @start_date = @period_days.days.ago.to_date
    @end_date = Date.current

    model = audit_log_model
    @stats = model.overview_stats(start_date: @start_date, end_date: @end_date)
    @daily_totals = model.daily_totals(start_date: @start_date, end_date: @end_date)
    @provider_summary = model.provider_summary(start_date: @start_date, end_date: @end_date)

    logs_scope = model.in_period(@start_date, @end_date)
                      .by_provider(params[:provider])
                      .recent
    @pagy, @logs = pagy(logs_scope, limit: 50)
  end

  private

  def audit_log_model
    @audit_mode == "plaid" ? PlaidApiLog : ApiRequestLog
  end

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
