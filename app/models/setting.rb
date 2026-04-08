# Dynamic settings the user can change within the app (helpful for self-hosting)
class Setting < RailsSettings::Base
  cache_prefix { "v1" }

  field :synth_api_key, type: :string, default: ENV["SYNTH_API_KEY"]
  field :openai_access_token, type: :string, default: ENV["OPENAI_ACCESS_TOKEN"]
  field :site_name, type: :string, default: ENV["APP_NAME"]
  field :site_logo_url, type: :string, default: ENV["APP_LOGO_URL"]
  field :website_url, type: :string, default: ENV["APP_WEBSITE_URL"]
  field :privacy_policy_url, type: :string, default: ENV["PRIVACY_POLICY_URL"]
  field :terms_of_service_url, type: :string, default: ENV["TERMS_OF_SERVICE_URL"]

  field :require_invite_for_signup, type: :boolean, default: false
  field :require_email_confirmation, type: :boolean, default: ENV.fetch("REQUIRE_EMAIL_CONFIRMATION", "true") == "true"
end
