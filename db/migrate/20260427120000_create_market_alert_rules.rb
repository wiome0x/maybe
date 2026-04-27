class CreateMarketAlertRules < ActiveRecord::Migration[7.2]
  def change
    create_table :market_alert_rules, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.string  :symbol,          null: false          # e.g. "^GSPC", "AAPL", or "*" for all watchlist
      t.string  :name                                  # display label, e.g. "S&P 500"
      t.string  :condition,       null: false          # "change_percent_below" | "change_percent_above"
      t.decimal :threshold,       null: false, precision: 8, scale: 4  # e.g. -5.0
      t.boolean :enabled,         null: false, default: true
      t.timestamps
    end

    add_index :market_alert_rules, :user_id, if_not_exists: true
    add_index :market_alert_rules, [ :user_id, :symbol, :condition ], unique: true, if_not_exists: true
  end
end
