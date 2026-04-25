class Settings::BarkNotificationSettingsController < ApplicationController
  layout "settings"

  def show
    @subscription = Current.user.bark_notification_subscription || Current.user.build_bark_notification_subscription
    load_form_options
  end

  def update
    @subscription = Current.user.bark_notification_subscription || Current.user.build_bark_notification_subscription

    if @subscription.update(subscription_params)
      redirect_to settings_bark_notification_path, notice: t(".success")
    else
      load_form_options
      render :show, status: :unprocessable_entity
    end
  end

  def test
    @subscription = Current.user.bark_notification_subscription || Current.user.build_bark_notification_subscription

    unless @subscription.configured?
      redirect_to settings_bark_notification_path, alert: t(".missing_configuration")
      return
    end

    BarkNotifier.new(@subscription).deliver(
      title: t(".title"),
      body: t(".body"),
      url: market_stocks_news_url
    )

    redirect_to settings_bark_notification_path, notice: t(".success")
  rescue => error
    redirect_to settings_bark_notification_path, alert: t(".failure", error: error.message)
  end

  private
    def subscription_params
      params.require(:bark_notification_subscription).permit(
        :enabled, :server_url, :device_key, :delivery_frequency, :digest_hour, :timezone, :group_name, :sound, :icon,
        push_categories: []
      )
    end

    def load_form_options
      @category_options = BarkNotificationSubscription::PUSH_CATEGORIES.map do |category|
        [ t(".categories.#{category}"), category ]
      end
      @frequency_options = BarkNotificationSubscription::DELIVERY_FREQUENCIES.map do |frequency|
        [ t(".frequencies.#{frequency}"), frequency ]
      end
      @hour_options = 24.times.map { |hour| [ format("%02d:00", hour), hour ] }
    end
end
