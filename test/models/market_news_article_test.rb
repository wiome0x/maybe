require "test_helper"

class MarketNewsArticleTest < ActiveSupport::TestCase
  setup do
    MarketNewsArticle.delete_all
  end

  test "is stale when empty" do
    assert MarketNewsArticle.stale?
  end

  test "converts persisted rows to feed items" do
    article = MarketNewsArticle.create!(
      source: "CNBC",
      title: "Headline",
      url: "https://www.cnbc.com/example",
      published_at: Time.utc(2026, 4, 25, 8, 0, 0),
      translated_title: "中文标题",
      fetched_at: Time.utc(2026, 4, 25, 8, 5, 0)
    )

    item = MarketNewsArticle.latest_feed.first

    assert_equal article.source, item.source
    assert_equal article.title, item.title
    assert_equal article.url, item.url
    assert_equal article.published_at, item.published_at
    assert_equal article.translated_title, item.translated_title
  end
end
