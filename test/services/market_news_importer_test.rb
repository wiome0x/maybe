require "test_helper"

class MarketNewsImporterTest < ActiveSupport::TestCase
  setup do
    MarketNewsArticle.delete_all
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
