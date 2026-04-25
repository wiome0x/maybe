class AddBrokerConnectionToApiRequestLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :api_request_logs, :broker_connection_id, :uuid
    add_index :api_request_logs, :broker_connection_id
  end
end
