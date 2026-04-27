class ScheduledBrokerSyncJob < ApplicationJob
  queue_as :scheduled

  # Triggered daily by cron (see config/schedule.yml).
  # Syncs only BrokerConnections (e.g. Binance) — Plaid items have their own
  # webhook-driven sync mechanism and must not be triggered here.
  def perform
    track_run("sync_broker_connections") do |run|
      count = 0
      BrokerConnection.joins(:account)
                      .where(status: "active")
                      .where(accounts: { status: "active" })
                      .find_each do |broker_connection|
        broker_connection.sync_later
        count += 1
      rescue => e
        Rails.logger.error(
          "[ScheduledBrokerSyncJob] Failed to enqueue sync for BrokerConnection #{broker_connection.id}: #{e.message}"
        )
      end
      run.records_written = count
    end
  end
end
