class Settings::HostingsController < ApplicationController
  layout "settings"

  guard_feature unless: -> { self_hosted? }

  before_action :ensure_admin, only: :clear_cache

  def show
    synth_provider = Provider::Registry.get_provider(:synth)
    @synth_usage = synth_provider&.usage
  end

  def update
    if hosting_params.key?(:require_invite_for_signup)
      Setting.require_invite_for_signup = hosting_params[:require_invite_for_signup]
    end

    if hosting_params.key?(:require_email_confirmation)
      Setting.require_email_confirmation = hosting_params[:require_email_confirmation]
    end

    if hosting_params.key?(:synth_api_key)
      Setting.synth_api_key = hosting_params[:synth_api_key]
    end

    if hosting_params.key?(:site_name)
      Setting.site_name = hosting_params[:site_name]
    end

    if hosting_params.key?(:site_logo_url)
      Setting.site_logo_url = hosting_params[:site_logo_url]
    end

    if hosting_params.key?(:website_url)
      Setting.website_url = hosting_params[:website_url]
    end

    if hosting_params.key?(:privacy_policy_url)
      Setting.privacy_policy_url = hosting_params[:privacy_policy_url]
    end

    if hosting_params.key?(:terms_of_service_url)
      Setting.terms_of_service_url = hosting_params[:terms_of_service_url]
    end

    redirect_to settings_hosting_path, notice: t(".success")
  rescue ActiveRecord::RecordInvalid => error
    flash.now[:alert] = t(".failure")
    render :show, status: :unprocessable_entity
  end

  def clear_cache
    DataCacheClearJob.perform_later(Current.family)
    redirect_to settings_hosting_path, notice: t(".cache_cleared")
  end

  private
    def hosting_params
      params.require(:setting).permit(
        :require_invite_for_signup,
        :require_email_confirmation,
        :synth_api_key,
        :site_name,
        :site_logo_url,
        :website_url,
        :privacy_policy_url,
        :terms_of_service_url
      )
    end

    def ensure_admin
      redirect_to settings_hosting_path, alert: t(".not_authorized") unless Current.user.admin?
    end
end
