class CreateMarketSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :market_snapshots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :symbol,         null: false
      t.string  :name
      t.date    :date,           null: false
      t.string  :item_type,      null: false
      t.decimal :price,          precision: 19, scale: 4
      t.decimal :open_price,     precision: 19, scale: 4
      t.decimal :prev_close,     precision: 19, scale: 4
      t.decimal :high,           precision: 19, scale: 4
      t.decimal :low,            precision: 19, scale: 4
      t.decimal :change_percent, precision: 8,  scale: 4
      t.bigint  :volume
      t.bigint  :market_cap
      t.string  :currency,       default: "USD"
      t.string  :source
      t.timestamps
    end

    add_index :market_snapshots, [ :symbol, :date ], unique: true
    add_index :market_snapshots, :date
    add_index :market_snapshots, :item_type
  end
end
