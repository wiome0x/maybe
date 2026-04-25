class BrokerConnection < ApplicationRecord
  include Syncable

  belongs_to :account
  belongs_to :family

  if Rails.application.credentials.active_record_encryption.present?
    encrypts :api_key, :api_secret                 # Binance
    encrypts :access_token, :refresh_token         # Schwab
  end

  enum :provider, { binance: "binance", schwab: "schwab" }
  enum :status,   { active: "active", error: "error", requires_reauth: "requires_reauth" }

  validates :provider, :status, :connected_at, presence: true

  before_destroy :revoke_credentials!

  # Saves the raw account/positions snapshot from the broker API
  def upsert_account_snapshot!(payload)
    update!(raw_account_payload: payload, last_snapshot_at: Time.current)
  end

  # Saves the raw transactions snapshot from the broker API
  def upsert_transactions_snapshot!(payload)
    update!(raw_transactions_payload: payload, last_snapshot_at: Time.current)
  end

  # Clears imported data and re-processes from the stored snapshot.
  # Mirrors PlaidItem#authoritative_rebuild_and_sync_later.
  def rebuild_from_snapshot!
    # entries table has no broker_connection_id yet; destroy all account entries
    account.entries.destroy_all
    account.holdings.delete_all
    account.balances.delete_all
    BrokerConnection::Processor.new(self).process
    account.sync_later
  end

  private
    def revoke_credentials!
      # Schwab supports OAuth token revocation; Binance does not — credentials are simply cleared locally on destroy.
      if schwab? && access_token.present?
        Provider::Schwab.new(access_token: access_token).revoke_token!
      end
    rescue => e
      Rails.logger.warn("[BrokerConnection] Failed to revoke credentials: #{e.message}")
    end
end
