class PlaidItemsController < ApplicationController
  before_action :set_plaid_item, only: %i[edit destroy sync authoritative_rebuild]
  before_action :require_mfa_for_plaid!, except: :destroy

  def new
    region = params[:region] == "eu" ? :eu : :us
    webhooks_url = region == :eu ? plaid_eu_webhooks_url : plaid_us_webhooks_url

    Rails.logger.tagged("PlaidLink") do
      Rails.logger.info("Requesting link token | family=#{Current.family.id} region=#{region} accountable_type=#{params[:accountable_type]} webhooks_url=#{webhooks_url}")
    end

    @link_token = Current.family.get_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
      accountable_type: params[:accountable_type] || "Depository",
      region: region
    )

    Rails.logger.tagged("PlaidLink") do
      if @link_token.present?
        Rails.logger.info("Link token obtained successfully | family=#{Current.family.id} region=#{region}")
      else
        Rails.logger.warn("Link token is nil — Plaid may not be configured | family=#{Current.family.id} region=#{region}")
      end
    end
  end

  def edit
    webhooks_url = @plaid_item.plaid_region == "eu" ? plaid_eu_webhooks_url : plaid_us_webhooks_url

    @link_token = @plaid_item.get_update_link_token(
      webhooks_url: webhooks_url,
      redirect_url: accounts_url,
    )
  end

  def create
    Rails.logger.tagged("PlaidLink") do
      Rails.logger.info("Exchanging public token | family=#{Current.family.id} region=#{plaid_item_params[:region]} institution=#{item_name}")
    end

    Current.family.create_plaid_item!(
      public_token: plaid_item_params[:public_token],
      item_name: item_name,
      region: plaid_item_params[:region]
    )

    Rails.logger.tagged("PlaidLink") do
      Rails.logger.info("PlaidItem created and sync enqueued | family=#{Current.family.id} institution=#{item_name}")
    end

    redirect_to accounts_path, notice: t(".success")
  end

  def destroy
    @plaid_item.destroy_later
    redirect_to accounts_path, notice: t(".success")
  end

  def sync
    unless @plaid_item.syncing?
      @plaid_item.sync_later
    end

    respond_to do |format|
      format.html { redirect_back_or_to accounts_path }
      format.json { head :ok }
    end
  end

  def authoritative_rebuild
    result = @plaid_item.authoritative_rebuild_and_sync_later

    redirect_back_or_to(
      accounts_path,
      notice: t(
        ".success",
        entries: result[:imported_entries],
        holdings: result[:holdings],
        balances: result[:balances]
      )
    )
  rescue => e
    Rails.logger.error("[PlaidItemsController] authoritative_rebuild failed for PlaidItem##{@plaid_item.id}: #{e.class} - #{e.message}")
    redirect_back_or_to(accounts_path, alert: t(".error"))
  end

  private
    def require_mfa_for_plaid!
      return if Current.user.otp_required?

      redirect_to settings_security_path, alert: t("plaid_items.security.mfa_required")
    end

    def set_plaid_item
      @plaid_item = Current.family.plaid_items.find(params[:id])
    end

    def plaid_item_params
      params.require(:plaid_item).permit(:public_token, :region, metadata: {})
    end

    def item_name
      plaid_item_params.dig(:metadata, :institution, :name)
    end

    def plaid_us_webhooks_url
      return webhooks_plaid_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/plaid"
    end

    def plaid_eu_webhooks_url
      return webhooks_plaid_eu_url if Rails.env.production?

      ENV.fetch("DEV_WEBHOOKS_URL", root_url.chomp("/")) + "/webhooks/plaid_eu"
    end
end
