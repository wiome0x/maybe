class CreateBarkNotificationSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :bark_notification_subscriptions, id: :uuid do |t|
      t.uuid :user_id, null: false
      t.boolean :enabled, null: false, default: false
      t.string :server_url, null: false, default: "https://api.day.app"
      t.string :device_key
      t.string :push_categories, null: false, default: [], array: true
      t.string :delivery_frequency, null: false, default: "realtime"
      t.integer :digest_hour, null: false, default: 8
      t.string :timezone, null: false
      t.string :group_name
      t.string :sound
      t.string :icon
      t.timestamps
    end

    add_index :bark_notification_subscriptions, :user_id, unique: true
    add_foreign_key :bark_notification_subscriptions, :users
  end
end
