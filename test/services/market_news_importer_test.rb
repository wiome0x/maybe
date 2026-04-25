require "test_helper"

class MarketNewsImporterTest < ActiveSupport::TestCase
  setup do
    MarketNewsArticle.delete_all
    BarkNotification.delete_all
    BarkNotificationSubscription.delete_all
  end

  test "imports and upserts fetched market news" do
    now = Time.utc(2026, 4, 25, 9, 0, 0)
    feed = stub
    translator = stub
    items = [
      MarketNewsFeed::Item.new(
        source: "CNBC",
        title: "Opening bell rally",
        url: "https://www.cnbc.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: nil
      )
    ]
    translated_items = [
      items.first.with(translated_title: "开盘走强")
    ]
    updated_items = [
      items.first.with(title: "Updated headline")
    ]
    updated_translated_items = [
      updated_items.first.with(translated_title: "更新后的标题")
    ]

    feed.expects(:fetch).with(force_refresh: true).twice.returns(items, updated_items)
    translator.expects(:translate_items).with(items, locale: :"zh-CN").returns(translated_items)
    translator.expects(:translate_items).with(updated_items, locale: :"zh-CN").returns(updated_translated_items)

    importer = MarketNewsImporter.new(feed: feed, translator: translator, now: now)

    assert_equal 1, importer.import
    assert_equal 1, MarketNewsArticle.count
    assert_equal "Opening bell rally", MarketNewsArticle.first.title
    assert_equal "开盘走强", MarketNewsArticle.first.translated_title

    assert_equal 1, importer.import
    assert_equal 1, MarketNewsArticle.count
    assert_equal "Updated headline", MarketNewsArticle.first.title
    assert_equal "更新后的标题", MarketNewsArticle.first.translated_title
  end

  test "queues bark notifications for subscribed users" do
    user = users(:family_admin)
    user.create_bark_notification_subscription!(
      enabled: true,
      device_key: "abc123",
      push_categories: [ "market_news" ],
      delivery_frequency: "realtime",
      timezone: "Asia/Shanghai"
    )

    now = Time.utc(2026, 4, 25, 9, 0, 0)
    feed = stub
    translator = stub
    items = [
      MarketNewsFeed::Item.new(
        source: "Bloomberg",
        title: "Treasuries climb",
        url: "https://www.bloomberg.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: nil
      ),
      MarketNewsFeed::Item.new(
        source: "Fed",
        title: "Powell comments on inflation",
        url: "https://www.federalreserve.gov/example",
        published_at: Time.utc(2026, 4, 25, 8, 10, 0),
        translated_title: nil
      )
    ]
    translated_items = [
      items.first.with(translated_title: "美债走高"),
      items.second.with(translated_title: "鲍威尔谈通胀")
    ]

    feed.expects(:fetch).with(force_refresh: true).returns(items)
    translator.expects(:translate_items).with(items, locale: :"zh-CN").returns(translated_items)

    assert_difference -> { BarkNotification.count }, 2 do
      MarketNewsImporter.new(feed: feed, translator: translator, now: now).import
    end

    notifications = BarkNotification.order(:created_at).to_a

    assert_equal [ user, user ], notifications.map(&:user)
    assert_equal [ "market_news", "market_news" ], notifications.map(&:category)
    assert_equal [ "美债走高", "鲍威尔谈通胀" ], notifications.map(&:title)
    assert_equal "https://example.com/markets/stocks/news", notifications.first.target_url
    assert_equal "Bloomberg: 美债走高", notifications.first.body
    assert_equal "Fed: 鲍威尔谈通胀", notifications.second.body
    assert_equal Time.utc(2026, 4, 26, 0, 0, 0), notifications.first.scheduled_for
    assert_equal Time.utc(2026, 4, 26, 0, 0, 0), notifications.second.scheduled_for
    assert_equal notifications.first.batch_key, notifications.second.batch_key
  end

  test "marketwatch feed list includes realtime and bulletin streams" do
    urls = MarketNewsFeed::FEEDS.select { |feed| feed[:source] == "MarketWatch" }.map { |feed| feed[:url] }

    assert_includes urls, "https://feeds.content.dowjones.io/public/rss/mw_topstories"
    assert_includes urls, "https://feeds.content.dowjones.io/public/rss/mw_realtimeheadlines"
    assert_includes urls, "https://feeds.content.dowjones.io/public/rss/mw_marketpulse"
    assert_includes urls, "https://feeds.content.dowjones.io/public/rss/mw_bulletins"
  end

  test "feed list includes bloomberg and fed sources" do
    bloomberg_urls = MarketNewsFeed::FEEDS.select { |feed| feed[:source] == "Bloomberg" }.map { |feed| feed[:url] }
    fed_urls = MarketNewsFeed::FEEDS.select { |feed| feed[:source] == "Fed" }.map { |feed| feed[:url] }

    assert_includes bloomberg_urls, "https://feeds.bloomberg.com/markets/news.rss"
    assert_includes fed_urls, "https://www.federalreserve.gov/feeds/press_monetary.xml"
    assert_includes fed_urls, "https://www.federalreserve.gov/feeds/speeches.xml"
    assert_includes fed_urls, "https://www.federalreserve.gov/feeds/press_all.xml"
  end
end
