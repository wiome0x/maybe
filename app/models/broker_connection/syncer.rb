class BrokerConnection::Syncer
  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def perform_sync(sync)
    Rails.logger.tagged("BrokerConnection::Syncer", broker_connection.id) do
      guard_sync_rate!
      @current_sync_id = sync.id
      import_latest_broker_data
      process_broker_data
      broker_connection.account.sync_later(parent_sync: sync)
    end
  rescue Provider::Error => e
    handle_provider_error(e)
    raise
  end

  def perform_post_sync
    # Trigger family-level post-sync tasks (rules, transfer matching) that would
    # normally run via Family::Syncer when the sync is login-driven.
    broker_connection.family.rules.active.find_each(&:apply_later)
    broker_connection.family.auto_match_transfers!
  end

  private
    def import_latest_broker_data
      provider = build_provider

      account_result = provider.fetch_account_data
      raise account_result.error unless account_result.success?

      # Pass balances to fetch_trade_history so Binance doesn't make a redundant /account call.
      balances = account_result.data.is_a?(Hash) ? account_result.data["balances"] : nil
      transactions_result = fetch_transactions(provider, balances: balances)
      raise transactions_result.error unless transactions_result.success?

      broker_connection.upsert_account_snapshot!(account_result.data)
      broker_connection.upsert_transactions_snapshot!(transactions_result.data)
    end

    def fetch_transactions(provider, balances: nil)
      if broker_connection.binance?
        provider.fetch_trade_history(since: last_sync_date, balances: balances)
      else
        provider.fetch_transaction_history(since: last_sync_date)
      end
    end

    def process_broker_data
      BrokerConnection::Processor.new(broker_connection).process
    end

    def build_provider
      case broker_connection.provider
      when "binance"
        provider = Provider::Binance.new(
          api_key: broker_connection.api_key,
          api_secret: broker_connection.api_secret,
          broker_connection: broker_connection
        )
      when "schwab"
        provider = Provider::Schwab.new(
          access_token: broker_connection.access_token,
          refresh_token: broker_connection.refresh_token,
          broker_connection: broker_connection
        )
      end
      provider.audit_sync_id = @current_sync_id
      provider
    end

    def last_sync_date
      broker_connection.last_synced_at&.to_date || 2.years.ago.to_date
    end

    def handle_provider_error(error)
      new_status = error.message.include?("auth") ? "requires_reauth" : "error"
      broker_connection.update!(status: new_status, error_message: error.message)
    end

    # Binance enforces a request weight limit (1200/min, 6000/5min).
    # Guard against runaway syncs: if this connection has already synced
    # more than MAX_SYNCS_PER_DAY times today, skip and log a warning.
    MAX_SYNCS_PER_DAY = 10

    def guard_sync_rate!
      todays_count = broker_connection.syncs
                                      .where(created_at: Time.current.beginning_of_day..)
                                      .count

      if todays_count >= MAX_SYNCS_PER_DAY
        raise Provider::Error.new(
          "Binance sync rate guard: #{broker_connection.id} has already synced #{todays_count} times today"
        )
      end
    end
end
