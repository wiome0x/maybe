class PlaidItem < ApplicationRecord
  include Syncable, Provided

  enum :plaid_region, { us: "us", eu: "eu" }
  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  if Rails.application.credentials.active_record_encryption.present?
    encrypts :access_token, deterministic: true
  end

  validates :name, :access_token, presence: true

  before_destroy :remove_plaid_item

  belongs_to :family
  has_one_attached :logo

  has_many :plaid_accounts, dependent: :destroy
  has_many :accounts, through: :plaid_accounts

  scope :active, -> { where(scheduled_for_deletion: false) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def get_update_link_token(webhooks_url:, redirect_url:)
    family.get_link_token(
      webhooks_url: webhooks_url,
      redirect_url: redirect_url,
      region: plaid_region,
      access_token: access_token
    )
  rescue Plaid::ApiError => e
    error_body = JSON.parse(e.response_body)

    if error_body["error_code"] == "ITEM_NOT_FOUND"
      # Mark the connection as invalid but don't auto-delete
      update!(status: :requires_update)
    end

    Sentry.capture_exception(e)
    nil
  end

  def destroy_later
    Rails.logger.info("[PlaidItem] Scheduling deletion for PlaidItem##{id} (#{name})")
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  def import_latest_plaid_data
    PlaidItem::Importer.new(self, plaid_provider: plaid_provider).import
  end

  # Reads the fetched data and updates internal domain objects
  # Generally, this should only be called within a "sync", but can be called
  # manually to "re-sync" the already fetched data
  def process_accounts
    plaid_accounts.each do |plaid_account|
      PlaidAccount::Processor.new(plaid_account).process
    end
  end

  # Rebuilds this Plaid item from source-of-truth data:
  # 1) Remove imported entries (plaid-backed only)
  # 2) Remove derived holdings and balances
  # 3) Reset transaction cursor and trigger a fresh sync
  #
  # Returns a hash of deleted row counts + sync metadata.
  def authoritative_rebuild_and_sync_later
    deleted = {
      imported_entries: 0,
      holdings: 0,
      balances: 0
    }

    ActiveRecord::Base.transaction do
      accounts.find_each do |account|
        deleted[:imported_entries] += account.entries.where.not(plaid_id: nil).delete_all
        deleted[:holdings] += account.holdings.delete_all
        deleted[:balances] += account.balances.delete_all
      end

      update!(next_cursor: nil)
    end

    sync = sync_later

    deleted.merge(sync_id: sync&.id, sync_status: sync&.status)
  end

  # Once all the data is fetched, we can schedule account syncs to calculate historical balances
  def schedule_account_syncs(parent_sync: nil, window_start_date: nil, window_end_date: nil)
    accounts.each do |account|
      account.sync_later(
        parent_sync: parent_sync,
        window_start_date: window_start_date,
        window_end_date: window_end_date
      )
    end
  end

  # Saves the raw data fetched from Plaid API for this item
  def upsert_plaid_snapshot!(item_snapshot)
    assign_attributes(
      available_products: item_snapshot.available_products,
      billed_products: item_snapshot.billed_products,
      raw_payload: item_snapshot,
    )

    save!
  end

  # Saves the raw data fetched from Plaid API for this item's institution
  def upsert_plaid_institution_snapshot!(institution_snapshot)
    assign_attributes(
      institution_id: institution_snapshot.institution_id,
      institution_url: institution_snapshot.url,
      institution_color: institution_snapshot.primary_color,
      raw_institution_payload: institution_snapshot
    )

    save!
  end

  def supports_product?(product)
    supported_products.include?(product)
  end

  private
    def remove_plaid_item
      Rails.logger.info("[PlaidItem] Removing Plaid item #{plaid_id} via API")
      plaid_provider.remove_item(access_token)
      Rails.logger.info("[PlaidItem] Successfully removed Plaid item #{plaid_id}")
    rescue Plaid::ApiError => e
      json_response = JSON.parse(e.response_body)
      error_code = json_response["error_code"]
      Rails.logger.warn("[PlaidItem] Plaid API error removing item #{plaid_id}: #{error_code} - #{json_response['error_message']}")

      # Allow deletion to proceed for non-recoverable Plaid errors:
      # - ITEM_NOT_FOUND: already deleted on Plaid side
      # - INVALID_ACCESS_TOKEN: token from a different environment (e.g. sandbox vs production)
      unless %w[ITEM_NOT_FOUND INVALID_ACCESS_TOKEN].include?(error_code)
        raise e
      end
    rescue => e
      Rails.logger.error("[PlaidItem] Unexpected error removing Plaid item #{plaid_id}: #{e.class} - #{e.message}")
      raise e
    end

    # Plaid returns mutually exclusive arrays here.  If the item has made a request for a product,
    # it is put in the billed_products array.  If it is supported, but not yet used, it goes in the
    # available_products array.
    def supported_products
      available_products + billed_products
    end
end
