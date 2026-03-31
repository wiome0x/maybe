class CreateHistoricalPrices < ActiveRecord::Migration[7.2]
  def change
    create_table :historical_prices, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :security, null: false, foreign_key: true, type: :uuid
      t.references :import, foreign_key: true, type: :uuid
      t.date :date, null: false
      t.decimal :open, precision: 19, scale: 4
      t.decimal :high, precision: 19, scale: 4
      t.decimal :low, precision: 19, scale: 4
      t.decimal :close, precision: 19, scale: 4, null: false
      t.decimal :volume, precision: 19, scale: 4
      t.string :ticker, null: false
      t.string :currency, default: "USD", null: false

      t.timestamps
    end

    add_index :historical_prices, [ :family_id, :security_id, :date ], unique: true, name: "idx_hist_prices_family_security_date"
    add_index :historical_prices, [ :family_id, :ticker, :date ]
    add_index :historical_prices, [ :family_id, :ticker ]
  end
end
