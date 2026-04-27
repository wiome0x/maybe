class Settings::MarketAlertRulesController < ApplicationController
  layout "settings"

  def create
    @rule = Current.user.market_alert_rules.build(rule_params)

    if @rule.save
      redirect_to settings_bark_notification_path, notice: "Alert rule added."
    else
      redirect_to settings_bark_notification_path, alert: @rule.errors.full_messages.to_sentence
    end
  end

  def destroy
    Current.user.market_alert_rules.find(params[:id]).destroy!
    redirect_to settings_bark_notification_path, notice: "Alert rule removed."
  end

  private

    def rule_params
      params.require(:market_alert_rule).permit(:symbol, :name, :condition, :threshold, :enabled)
    end
end
