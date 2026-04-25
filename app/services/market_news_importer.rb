class MarketNewsImporter
  def initialize(feed: MarketNewsFeed, translator: MarketNewsTranslator, now: Time.current)
    @feed = feed
    @translator = translator
    @now = now
  end

  def import
    items = feed.fetch(force_refresh: true)
    return 0 if items.empty?

    translated_items = translator.translate_items(items, locale: :"zh-CN")

    MarketNewsArticle.upsert_all(
      translated_items.map do |item|
        {
          source: item.source,
          title: item.title,
          url: item.url,
          published_at: item.published_at,
          translated_title: item.translated_title,
          fetched_at: now,
          created_at: now,
          updated_at: now
        }
      end,
      unique_by: :index_market_news_articles_on_source_and_url
    )

    translated_items.count
  rescue => e
    Rails.logger.warn("Market news import failed: #{e.class}: #{e.message}")
    0
  end

  private
    attr_reader :feed, :translator, :now
end
