class Settings::WeeklyReportSettingsController < ApplicationController
  layout "settings"

  def show
    @subscription = Current.user.weekly_report_subscription || Current.user.build_weekly_report_subscription
    @recent_reports = Current.user.weekly_reports.ordered.limit(5)
    load_form_options
  end

  def update
    @subscription = Current.user.weekly_report_subscription || Current.user.build_weekly_report_subscription

    if @subscription.update(subscription_params)
      redirect_to settings_weekly_report_path, notice: t(".success")
    else
      @recent_reports = Current.user.weekly_reports.ordered.limit(5)
      load_form_options
      render :show, status: :unprocessable_entity
    end
  end

  private
    def subscription_params
      params.require(:weekly_report_subscription).permit(
        :enabled, :send_weekday, :send_hour, :timezone, :period_key,
        extra_recipient_emails: []
      )
    end

    def load_form_options
      @weekday_options = I18n.t("date.day_names").each_with_index.map { |day, index| [ day, index ] }
      @hour_options = 24.times.map { |hour| [ format("%02d:00", hour), hour ] }
    end
end
