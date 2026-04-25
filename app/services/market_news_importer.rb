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

    enqueue_bark_notifications(translated_items)

    translated_items.count
  rescue => e
    Rails.logger.warn("Market news import failed: #{e.class}: #{e.message}")
    0
  end

  private
    attr_reader :feed, :translator, :now

    def enqueue_bark_notifications(items)
      BarkNotificationSubscription.enabled.includes(:user).find_each do |subscription|
        next unless subscription.configured?
        next unless subscription.wants_category?("market_news")

        items.each do |item|
          headline = item.translated_title.presence || item.title

          BarkNotificationScheduler.enqueue!(
            user: subscription.user,
            category: "market_news",
            title: headline,
            body: "#{item.source}: #{headline}",
            target_url: AppUrlBuilder.url_for(Rails.application.routes.url_helpers.market_stocks_news_path),
            source_key: "market_news_article:#{item.url}",
            occurred_at: item.published_at || now,
            payload: {
              source: item.source,
              article_url: item.url,
              published_at: item.published_at&.iso8601
            }
          )
        end
      end
    end
end
