class BrokerConnection::Syncer
  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def perform_sync(sync)
    Rails.logger.tagged("BrokerConnection::Syncer", broker_connection.id) do
      import_latest_broker_data
      process_broker_data
      broker_connection.account.sync_later(parent_sync: sync)
    end
  rescue Provider::Error => e
    handle_provider_error(e)
    raise
  end

  def perform_post_sync
    # no-op (balance recalculation is handled by the child account sync)
  end

  private
    def import_latest_broker_data
      provider = build_provider
      account_result = provider.fetch_account_data
      transactions_result = fetch_transactions(provider)

      broker_connection.upsert_account_snapshot!(account_result.data)
      broker_connection.upsert_transactions_snapshot!(transactions_result.data)
    end

    def fetch_transactions(provider)
      if broker_connection.binance?
        provider.fetch_trade_history(since: last_sync_date)
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
        Provider::Binance.new(
          api_key: broker_connection.api_key,
          api_secret: broker_connection.api_secret
        )
      when "schwab"
        Provider::Schwab.new(
          access_token: broker_connection.access_token,
          refresh_token: broker_connection.refresh_token,
          broker_connection: broker_connection
        )
      end
    end

    def last_sync_date
      broker_connection.last_synced_at&.to_date || 2.years.ago.to_date
    end

    def handle_provider_error(error)
      new_status = error.message.include?("auth") ? "requires_reauth" : "error"
      broker_connection.update!(status: new_status, error_message: error.message)
    end
end
