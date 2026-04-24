class CreateWeeklyReports < ActiveRecord::Migration[7.2]
  def change
    create_table :weekly_report_subscriptions, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.integer :send_weekday, null: false, default: 1
      t.integer :send_hour, null: false, default: 8
      t.string :timezone, null: false
      t.string :period_key, null: false, default: "last_7_days"
      t.timestamps
    end

    create_table :weekly_reports, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.date :period_start_date, null: false
      t.date :period_end_date, null: false
      t.datetime :scheduled_for, null: false
      t.datetime :sent_at
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, null: false, default: {}
      t.text :html_body
      t.text :text_body
      t.text :error_message
      t.timestamps
    end

    add_index :weekly_reports, [ :user_id, :period_start_date, :period_end_date ], unique: true, name: "index_weekly_reports_on_user_and_period"
    add_index :weekly_reports, :scheduled_for
    add_index :weekly_reports, :status
  end
end
