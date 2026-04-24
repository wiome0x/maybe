class PlaidItem::WebhookProcessor
  MissingItemError = Class.new(StandardError)

  def initialize(webhook_body)
    parsed = JSON.parse(webhook_body)
    @webhook_type = parsed["webhook_type"]
    @webhook_code = parsed["webhook_code"]
    @item_id = parsed["item_id"]
    @error = parsed["error"]
  end

  def process
    Rails.logger.tagged("PlaidWebhook") do
      Rails.logger.info("Received | type=#{webhook_type} code=#{webhook_code} item_id=#{item_id}")
    end

    unless plaid_item
      Rails.logger.tagged("PlaidWebhook") do
        Rails.logger.error("PlaidItem not found | plaid_id=#{item_id} — cannot process webhook")
      end
      handle_missing_item
      return
    end

    case [ webhook_type, webhook_code ]
    when [ "TRANSACTIONS", "SYNC_UPDATES_AVAILABLE" ]
      Rails.logger.tagged("PlaidWebhook") do
        Rails.logger.info("Enqueuing sync | plaid_item=#{plaid_item.id} reason=TRANSACTIONS:SYNC_UPDATES_AVAILABLE")
      end
      plaid_item.sync_later
    when [ "INVESTMENTS_TRANSACTIONS", "DEFAULT_UPDATE" ]
      Rails.logger.tagged("PlaidWebhook") do
        Rails.logger.info("Enqueuing sync | plaid_item=#{plaid_item.id} reason=INVESTMENTS_TRANSACTIONS:DEFAULT_UPDATE")
      end
      plaid_item.sync_later
    when [ "HOLDINGS", "DEFAULT_UPDATE" ]
      Rails.logger.tagged("PlaidWebhook") do
        Rails.logger.info("Enqueuing sync | plaid_item=#{plaid_item.id} reason=HOLDINGS:DEFAULT_UPDATE")
      end
      plaid_item.sync_later
    when [ "ITEM", "ERROR" ]
      if error["error_code"] == "ITEM_LOGIN_REQUIRED"
        Rails.logger.tagged("PlaidWebhook") do
          Rails.logger.warn("ITEM_LOGIN_REQUIRED | plaid_item=#{plaid_item.id} — marking requires_update")
        end
        plaid_item.update!(status: :requires_update)
      else
        Rails.logger.tagged("PlaidWebhook") do
          Rails.logger.error("ITEM error | plaid_item=#{plaid_item.id} error_code=#{error['error_code']} message=#{error['error_message']}")
        end
      end
    else
      Rails.logger.tagged("PlaidWebhook") do
        Rails.logger.warn("Unhandled webhook | type=#{webhook_type} code=#{webhook_code} plaid_item=#{plaid_item.id}")
      end
    end
  rescue => e
    Rails.logger.tagged("PlaidWebhook") do
      Rails.logger.error("Webhook processing failed | #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    end
    # To always ensure we return a 200 to Plaid (to keep endpoint healthy), silently capture and report all errors
    Sentry.capture_exception(e)
  end

  private
    attr_reader :webhook_type, :webhook_code, :item_id, :error

    def plaid_item
      @plaid_item ||= PlaidItem.find_by(plaid_id: item_id)
    end

    def handle_missing_item
      return if plaid_item.present?

      # If we cannot find an item in our DB, that means we've reached an invalid data state where
      # the Plaid Item (upstream) still exists (and is being billed), but doesn't exist internally.
      #
      # Since we don't have the item which has the access token, there is nothing we can do programmatically
      # here, so we just need to report it to Sentry and manually handle it.
      Sentry.capture_exception(MissingItemError.new("Received Plaid webhook for item no longer in our DB.  Manual action required to resolve.")) do |scope|
        scope.set_tags(plaid_item_id: item_id)
      end
    end
end
