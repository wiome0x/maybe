class ScheduledBrokerSyncJob < ApplicationJob
  queue_as :scheduled

  # Triggered daily by cron (see config/schedule.yml).
  # Syncs only BrokerConnections (e.g. Binance) — Plaid items have their own
  # webhook-driven sync mechanism and must not be triggered here.
  def perform
    BrokerConnection.joins(:account)
                    .where(status: "active")
                    .where(accounts: { status: "active" })
                    .find_each do |broker_connection|
      broker_connection.sync_later
    rescue => e
      Rails.logger.error(
        "[ScheduledBrokerSyncJob] Failed to enqueue sync for BrokerConnection #{broker_connection.id}: #{e.message}"
      )
    end
  end
end
