class CreateApiRequestLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :api_request_logs, id: :uuid do |t|
      t.string :provider_name, null: false
      t.string :endpoint
      t.string :http_method
      t.string :request_status, null: false
      t.integer :response_code
      t.float :response_time_ms
      t.text :error_message
      t.datetime :requested_at, null: false

      t.timestamps
    end

    add_index :api_request_logs, [:provider_name, :requested_at], name: "idx_api_request_logs_provider_requested_at"
    add_index :api_request_logs, [:request_status], name: "idx_api_request_logs_status"
    add_index :api_request_logs, [:requested_at], name: "idx_api_request_logs_requested_at"
  end
end
