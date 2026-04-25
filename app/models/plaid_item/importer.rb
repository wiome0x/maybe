class PlaidItem::Importer
  def initialize(plaid_item, plaid_provider:, investments_start_date: nil, investments_end_date: Date.current)
    @plaid_item = plaid_item
    @plaid_provider = plaid_provider
    @investments_start_date = investments_start_date
    @investments_end_date = investments_end_date
  end

  def import
    Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
      Rails.logger.info("Starting import | institution=#{plaid_item.name}")
      fetch_and_import_item_data
      fetch_and_import_accounts_data
      Rails.logger.info("Import complete")
    end
  rescue Plaid::ApiError => e
    error_body = JSON.parse(e.response_body) rescue {}
    Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
      Rails.logger.error("Plaid API error | code=#{error_body['error_code']} type=#{error_body['error_type']} message=#{error_body['error_message']}")
    end
    handle_plaid_error(e)
  end

  private
    attr_reader :plaid_item, :plaid_provider, :investments_start_date, :investments_end_date

    # All errors that should halt the import should be re-raised after handling
    # These errors will propagate up to the Sync record and mark it as failed.
    def handle_plaid_error(error)
      error_body = JSON.parse(error.response_body)

      case error_body["error_code"]
      when "ITEM_LOGIN_REQUIRED"
        Rails.logger.warn("[PlaidItem::Importer] plaid_item=#{plaid_item.id} ITEM_LOGIN_REQUIRED — marking requires_update")
        plaid_item.update!(status: :requires_update)
      else
        Rails.logger.error("[PlaidItem::Importer] plaid_item=#{plaid_item.id} Unhandled Plaid error=#{error_body['error_code']} — re-raising")
        raise error
      end
    end

    def fetch_and_import_item_data
      Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
        Rails.logger.info("Fetching item + institution metadata")
      end

      item_data = plaid_provider.get_item(plaid_item.access_token).item
      institution_data = plaid_provider.get_institution(item_data.institution_id).institution

      Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
        Rails.logger.info("Institution fetched | institution_id=#{item_data.institution_id} name=#{institution_data.name} products=#{item_data.products.inspect}")
      end

      plaid_item.upsert_plaid_snapshot!(item_data)
      plaid_item.upsert_plaid_institution_snapshot!(institution_data)
    end

    def fetch_and_import_accounts_data
      snapshot = PlaidItem::AccountsSnapshot.new(
        plaid_item,
        plaid_provider: plaid_provider,
        investments_start_date: investments_start_date,
        investments_end_date: investments_end_date
      )

      Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
        Rails.logger.info("Fetched #{snapshot.accounts.size} accounts from Plaid")
      end

      PlaidItem.transaction do
        snapshot.accounts.each do |raw_account|
          Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
            Rails.logger.info("Importing account | plaid_account_id=#{raw_account.account_id} name=#{raw_account.name} type=#{raw_account.type}/#{raw_account.subtype}")
          end

          plaid_account = plaid_item.plaid_accounts.find_or_initialize_by(
            plaid_id: raw_account.account_id
          )

          PlaidAccount::Importer.new(
            plaid_account,
            account_snapshot: snapshot.get_account_data(raw_account.account_id)
          ).import
        end

        # Once we know all data has been imported, save the cursor to avoid re-fetching the same data next time
        cursor = snapshot.transactions_cursor
        plaid_item.update!(next_cursor: cursor)

        Rails.logger.tagged("PlaidItem::Importer", "plaid_item=#{plaid_item.id}") do
          Rails.logger.info("Cursor saved | next_cursor=#{cursor.present? ? '[present]' : 'nil'}")
        end
      end
    end
end
