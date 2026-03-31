class CreateWatchlistItems < ActiveRecord::Migration[7.2]
  def change
    create_table :watchlist_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :symbol, null: false
      t.string :name
      t.string :item_type, null: false  # "stock" or "crypto"
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :watchlist_items, [ :family_id, :symbol, :item_type ], unique: true
    add_index :watchlist_items, [ :family_id, :item_type, :position ]
  end
end
