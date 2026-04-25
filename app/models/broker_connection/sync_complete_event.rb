class BrokerConnection::SyncCompleteEvent
  attr_reader :broker_connection

  def initialize(broker_connection)
    @broker_connection = broker_connection
  end

  def broadcast
    # Delegate to the underlying account's sync complete event so the
    # accounts list row and sidebar groups are refreshed automatically.
    broker_connection.account.broadcast_sync_complete
  end
end
