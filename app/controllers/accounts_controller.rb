class AccountsController < ApplicationController
  before_action :set_account, only: %i[sync sparkline toggle_active show destroy hide unhide]
  include Periodable

  def index
    @draft_accounts = family.accounts.manual.broker_setup_pending.alphabetically
    @manual_accounts = family.accounts.manual.visible.where.not(id: @draft_accounts.select(:id)).alphabetically
    @plaid_items = family.plaid_items.ordered
    @hidden_accounts = family.accounts.hidden.alphabetically

    render layout: "settings"
  end

  def sync_all
    family.sync_later
    redirect_to accounts_path, notice: "Syncing accounts..."
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @tab = params[:tab]
    @q = params.fetch(:q, {}).permit(:search)
    entries = @account.entries.search(@q).reverse_chronological

    @pagy, @entries = pagy(entries, limit: params[:per_page] || "10")

    @activity_feed_data = Account::ActivityFeedData.new(@account, @entries)
  end

  def sync
    syncing = @account.syncing? || @account.broker_connection&.syncing?

    unless syncing
      if @account.broker_connection.present?
        @account.broker_connection.sync_later
      else
        @account.sync_later
      end
    end

    redirect_to account_path(@account)
  end

  def sparkline
    etag_key = @account.family.build_cache_key("#{@account.id}_sparkline", invalidate_on_data_updates: true)

    # Short-circuit with 304 Not Modified when the client already has the latest version.
    # We defer the expensive series computation until we know the content is stale.
    if stale?(etag: etag_key, last_modified: @account.family.latest_sync_completed_at)
      @sparkline_series = @account.sparkline_series
      render layout: false
    end
  end

  def toggle_active
    if @account.active?
      @account.disable!
    elsif @account.disabled?
      @account.enable!
    end
    redirect_to accounts_path
  end

  def hide
    @account.hide!
    redirect_to accounts_path, notice: "Account hidden"
  end

  def unhide
    @account.unhide_and_sync!
    redirect_to accounts_path, notice: "Account restored"
  end

  def destroy
    if @account.linked?
      plaid_item = @account.plaid_account&.plaid_item

      if plaid_item && plaid_item.accounts.count > 1
        # Multiple accounts under this Plaid connection — only unlink and delete this one
        Rails.logger.info("[AccountsController] Unlinking single account #{@account.id} from PlaidItem##{plaid_item.id}")
        @account.update!(plaid_account_id: nil)
        @account.destroy_later
        redirect_to accounts_path, notice: "Account scheduled for deletion"
      elsif plaid_item
        # Last account under this Plaid connection — delete the entire connection
        Rails.logger.info("[AccountsController] Deleting PlaidItem##{plaid_item.id} (last account #{@account.id})")
        plaid_item.destroy_later
        redirect_to accounts_path, notice: "Plaid connection and account scheduled for deletion"
      else
        Rails.logger.info("[AccountsController] Deleting orphaned linked account #{@account.id}")
        @account.destroy_later
        redirect_to accounts_path, notice: "Account scheduled for deletion"
      end
    else
      Rails.logger.info("[AccountsController] Deleting manual account #{@account.id}")
      @account.destroy_later
      redirect_to accounts_path, notice: "Account scheduled for deletion"
    end
  rescue => e
    Rails.logger.error("[AccountsController] Failed to schedule deletion for account #{@account.id}: #{e.class} - #{e.message}")
    redirect_to account_path(@account), alert: "Failed to delete account: #{e.message}"
  end

  private
    def family
      Current.family
    end

    def set_account
      @account = family.accounts.find(params[:id])
    end
end
