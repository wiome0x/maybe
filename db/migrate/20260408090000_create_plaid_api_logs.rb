class CreatePlaidApiLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :plaid_api_logs, id: :uuid do |t|
      t.uuid :plaid_item_id
      t.string :region, null: false
      t.string :source, null: false
      t.string :endpoint, null: false
      t.string :trigger
      t.boolean :success, null: false, default: false
      t.integer :duration_ms
      t.integer :http_status
      t.string :plaid_request_id
      t.string :webhook_type
      t.string :webhook_code
      t.jsonb :request_payload, null: false, default: {}
      t.jsonb :response_payload, null: false, default: {}
      t.jsonb :error_payload, null: false, default: {}
      t.datetime :requested_at, null: false

      t.timestamps
    end

    add_index :plaid_api_logs, :plaid_item_id
    add_index :plaid_api_logs, :requested_at
    add_index :plaid_api_logs, [ :source, :requested_at ]
    add_index :plaid_api_logs, [ :endpoint, :requested_at ]
    add_index :plaid_api_logs, [ :region, :requested_at ]
  end
end
