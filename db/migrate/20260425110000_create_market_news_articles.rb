class CreateMarketNewsArticles < ActiveRecord::Migration[7.2]
  def change
    create_table :market_news_articles, id: :uuid do |t|
      t.string :source, null: false
      t.text :title, null: false
      t.text :url, null: false
      t.datetime :published_at
      t.datetime :fetched_at, null: false

      t.timestamps
    end

    add_index :market_news_articles, [ :source, :url ], unique: true
    add_index :market_news_articles, :published_at
    add_index :market_news_articles, :fetched_at
  end
end
