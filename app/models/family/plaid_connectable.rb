module Family::PlaidConnectable
  extend ActiveSupport::Concern

  included do
    has_many :plaid_items, dependent: :destroy
  end

  def can_connect_plaid_us?
    plaid(:us).present?
  end

  # If Plaid provider is configured and user is in the EU region
  def can_connect_plaid_eu?
    plaid(:eu).present? && self.eu?
  end

  def create_plaid_item!(public_token:, item_name:, region:)
    Rails.logger.tagged("PlaidConnectable") do
      Rails.logger.info("Exchanging public token | family=#{id} region=#{region} institution=#{item_name}")
    end

    public_token_response = plaid(region).exchange_public_token(public_token)

    Rails.logger.tagged("PlaidConnectable") do
      Rails.logger.info("Token exchanged | family=#{id} plaid_item_id=#{public_token_response.item_id}")
    end

    plaid_item = plaid_items.create!(
      name: item_name,
      plaid_id: public_token_response.item_id,
      access_token: public_token_response.access_token,
      plaid_region: region
    )

    Rails.logger.tagged("PlaidConnectable") do
      Rails.logger.info("PlaidItem persisted | family=#{id} plaid_item=#{plaid_item.id} plaid_id=#{plaid_item.plaid_id}")
    end

    plaid_item.sync_later

    plaid_item
  end

  def get_link_token(webhooks_url:, redirect_url:, accountable_type: nil, region: :us, access_token: nil)
    return nil unless plaid(region)

    plaid(region).get_link_token(
      user_id: self.id,
      webhooks_url: webhooks_url,
      redirect_url: redirect_url,
      accountable_type: accountable_type,
      access_token: access_token
    ).link_token
  end

  private
    def plaid(region)
      Provider::Registry.plaid_provider_for_region(region)
    end
end
