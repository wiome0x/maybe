class StockInfoBootstrap
  LOCK_KEY = 1_835_204_917

  def self.perform!
    return if StockInfo.exists?

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      return unless acquire_lock(connection)

      begin
        return if StockInfo.exists?

        SyncStockInfosJob.perform_later
      ensure
        release_lock(connection)
      end
    end
  rescue ActiveRecord::DatabaseConnectionError, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid => e
    Rails.logger.warn("Skipping StockInfo bootstrap: #{e.class}: #{e.message}")
  end

  def self.acquire_lock(connection)
    locked = connection.select_value("SELECT pg_try_advisory_lock(#{LOCK_KEY})")
    ActiveModel::Type::Boolean.new.cast(locked)
  end

  def self.release_lock(connection)
    connection.select_value("SELECT pg_advisory_unlock(#{LOCK_KEY})")
  rescue => e
    Rails.logger.warn("Failed to release StockInfo bootstrap lock: #{e.class}: #{e.message}")
  end
  private_class_method :acquire_lock, :release_lock
end
