class AddTranslatedTitleToMarketNewsArticles < ActiveRecord::Migration[7.2]
  def change
    add_column :market_news_articles, :translated_title, :text
  end
end
