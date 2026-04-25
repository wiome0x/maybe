class CreateStockInfos < ActiveRecord::Migration[7.2]
  def change
    create_table :stock_infos, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :symbol, null: false
      t.string :sector
      t.string :sub_industry
      t.text :description_zh
      t.datetime :wikipedia_synced_at

      t.timestamps
    end

    add_index :stock_infos, :symbol, unique: true
  end
end
