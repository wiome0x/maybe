module Localize
  extend ActiveSupport::Concern

  included do
    around_action :switch_locale
    around_action :switch_timezone
  end

  private
    def switch_locale(&action)
      locale = Current.family.try(:locale) || browser_locale || I18n.default_locale
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
end
