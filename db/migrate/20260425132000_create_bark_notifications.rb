class CreateBarkNotifications < ActiveRecord::Migration[7.2]
  def change
    create_table :bark_notifications, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.string :category, null: false
      t.string :source_key, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.text :target_url
      t.datetime :scheduled_for, null: false
      t.string :batch_key, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :delivered_at
      t.text :error_message
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    add_index :bark_notifications, :user_id
    add_index :bark_notifications, :scheduled_for
    add_index :bark_notifications, :status
    add_index :bark_notifications, [ :user_id, :source_key ], unique: true
    add_index :bark_notifications, [ :user_id, :batch_key, :status ]
    add_foreign_key :bark_notifications, :users
  end
end
