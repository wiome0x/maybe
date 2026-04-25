class BrokerConnection::Processor
  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def process
    process_holdings
    process_trades
  end

  private
    def account
      broker_connection.account
    end

    def process_holdings
      # TODO: implement based on actual API response format
      # Reference: PlaidAccount::Investments::HoldingsProcessor
      # Key points:
      #   - Resolve securities via Security.find_or_create_by(ticker:)
      #   - Write daily holding snapshot via Holding.upsert_all
      Rails.logger.info("[BrokerConnection::Processor] process_holdings: pending implementation")
    end

    def process_trades
      # TODO: implement based on actual API response format
      # Reference: PlaidAccount::Investments::TransactionsProcessor
      # Key points:
      #   - Idempotency: find_or_initialize Entry by broker_trade_id
      #   - Trade qty sign convention: positive for buy, negative for sell (consistent with Maybe internals)
      #   - Generate entry name via Trade.build_name
      Rails.logger.info("[BrokerConnection::Processor] process_trades: pending implementation")
    end
end
