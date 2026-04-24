class AddPayloadsToApiRequestLogs < ActiveRecord::Migration[7.2]
  def change
    change_table :api_request_logs, bulk: true do |t|
      t.jsonb :request_payload, default: {}, null: false
      t.jsonb :response_payload, default: {}, null: false
      t.jsonb :error_payload, default: {}, null: false
    end
  end
end
