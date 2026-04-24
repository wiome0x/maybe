class PlaidItem::Syncer
  attr_reader :plaid_item

  def initialize(plaid_item)
    @plaid_item = plaid_item
  end

  def perform_sync(sync)
    Rails.logger.tagged("PlaidItem::Syncer", "plaid_item=#{plaid_item.id}") do
      Rails.logger.info("Starting sync | institution=#{plaid_item.name} plaid_id=#{plaid_item.plaid_id} sync=#{sync.id}")

      # Loads item metadata, accounts, transactions, and other data to our DB
      Rails.logger.info("Importing latest Plaid data...")
      plaid_item.import_latest_plaid_data

      # Processes the raw Plaid data and updates internal domain objects
      Rails.logger.info("Processing accounts...")
      plaid_item.process_accounts

      # All data is synced, so we can now run an account sync to calculate historical balances and more
      Rails.logger.info("Scheduling account syncs...")
      plaid_item.schedule_account_syncs(
        parent_sync: sync,
        window_start_date: sync.window_start_date,
        window_end_date: sync.window_end_date
      )

      Rails.logger.info("Sync complete | accounts=#{plaid_item.accounts.count}")
    end
  end

  def perform_post_sync
    # no-op
  end
end
