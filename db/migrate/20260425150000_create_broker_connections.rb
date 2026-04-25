class CreateBrokerConnections < ActiveRecord::Migration[7.2]
  def change
    create_table :broker_connections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid   :account_id,    null: false
      t.uuid   :family_id,     null: false
      t.string :provider,      null: false   # enum: "binance" | "schwab"
      t.string :status,        null: false, default: "active"
                                             # enum: "active" | "error" | "requires_reauth"
      t.datetime :connected_at, null: false

      # Binance: API Key / Secret (encrypted)
      t.text :encrypted_api_key
      t.text :encrypted_api_secret

      # Schwab: OAuth tokens (encrypted)
      t.text :encrypted_access_token
      t.text :encrypted_refresh_token
      t.datetime :token_expires_at

      # Raw snapshots (aligned with PlaidAccount raw_payload pattern)
      t.jsonb :raw_account_payload,      default: {}
      t.jsonb :raw_transactions_payload, default: {}
      t.datetime :last_snapshot_at

      # Sync metadata
      t.string :broker_account_id
      t.string :error_message

      t.timestamps
    end

    add_index :broker_connections, :account_id, unique: true   # one account, one connection
    add_index :broker_connections, :family_id
    add_index :broker_connections, :provider
    add_index :broker_connections, :status
  end
end
