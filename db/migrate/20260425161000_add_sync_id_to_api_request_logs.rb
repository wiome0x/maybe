class AddSyncIdToApiRequestLogs < ActiveRecord::Migration[7.2]
  def change
    add_column :api_request_logs, :sync_id, :uuid
    add_index  :api_request_logs, :sync_id
  end
end
