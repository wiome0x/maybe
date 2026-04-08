module BrandingHelper
  def app_display_name
    Setting.site_name.presence || ENV.fetch("APP_NAME", "Maybe Finance")
  end

  def app_logo_source
    Setting.site_logo_url.presence || "logomark-color.svg"
  end

  def app_website_url
    Setting.website_url.presence
  end

  def app_privacy_policy_url
    Setting.privacy_policy_url.presence || privacy_path
  end

  def app_terms_of_service_url
    Setting.terms_of_service_url.presence || terms_path
  end
end
