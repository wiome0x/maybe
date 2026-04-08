module Localize
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
    around_action :switch_timezone
  end

  private
    def switch_locale(&action)
      locale = resolved_locale
      session[:locale] = locale.to_s if locale.present?
      I18n.with_locale(locale, &action)
    end

    def switch_timezone(&action)
      timezone = Current.family.try(:timezone) || Time.zone
      Time.use_zone(timezone, &action)
    end

    def browser_locale
      request.compatible_language_from(I18n.available_locales)
    rescue StandardError
      nil
    end

    def resolved_locale
      requested = params[:locale].presence
      requested = requested&.to_s

      return requested if requested.present? && I18n.available_locales.map(&:to_s).include?(requested)

      stored = session[:locale].presence
      return stored if stored.present? && I18n.available_locales.map(&:to_s).include?(stored)

      Current.family.try(:locale) || browser_locale || I18n.default_locale
    end
end
