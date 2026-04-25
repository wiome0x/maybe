class MarketNewsImporter
  require "digest"

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

        summary_items = items.first(5)
        body = summary_items.map.with_index(1) do |item, index|
          headline = item.translated_title.presence || item.title
          "#{index}. #{headline}"
        end.join("\n")
        body = "#{body}\n+#{items.count - 5} more" if items.count > 5

        title =
          if items.one?
            summary_items.first.translated_title.presence || summary_items.first.title
          else
            "Market news summary (#{items.count})"
          end

        occurred_at = items.map(&:published_at).compact.max || now
        source_key = "market_news_summary:#{Digest::SHA256.hexdigest(items.map(&:url).sort.join('|'))}"

        BarkNotificationScheduler.enqueue!(
          user: subscription.user,
          category: "market_news",
          title: title,
          body: body,
          target_url: AppUrlBuilder.url_for(Rails.application.routes.url_helpers.market_stocks_news_path),
          source_key: source_key,
          occurred_at: occurred_at,
          payload: {
            article_count: items.count,
            sources: items.map(&:source).uniq,
            published_at: occurred_at&.iso8601
          }
        )
      end
    end
end
