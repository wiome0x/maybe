require "test_helper"

class MarketNewsImporterTest < ActiveSupport::TestCase
  setup do
    MarketNewsArticle.delete_all
  end

  test "imports and upserts fetched market news" do
    now = Time.utc(2026, 4, 25, 9, 0, 0)
    feed = stub
    items = [
      MarketNewsFeed::Item.new(
        source: "CNBC",
        title: "Opening bell rally",
        url: "https://www.cnbc.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: nil
      )
    ]

    feed.expects(:fetch).with(force_refresh: true).twice.returns(items, [
      items.first.with(title: "Updated headline")
    ])

    importer = MarketNewsImporter.new(feed: feed, now: now)

    assert_equal 1, importer.import
    assert_equal 1, MarketNewsArticle.count
    assert_equal "Opening bell rally", MarketNewsArticle.first.title

    assert_equal 1, importer.import
    assert_equal 1, MarketNewsArticle.count
    assert_equal "Updated headline", MarketNewsArticle.first.title
  end
end
