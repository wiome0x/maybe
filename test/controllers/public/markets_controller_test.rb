require "test_helper"

class Public::MarketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  test "should get public stocks heatmap without signing in" do
    Public::MarketsController.any_instance.stubs(:fetch_market_movers).returns([
      MarketQuote.new(
        symbol: "AAPL",
        name: "Apple",
        description: "Technology · Consumer Electronics",
        price: 210.12,
        change_percent: 4.25,
        volume: 1_000_000,
        market_cap: 3_000_000_000_000,
        logo_url: nil,
        item_type: "stock",
        open_price: 208.0,
        prev_close: 201.5,
        high: 211.0,
        low: 207.8
      )
    ])

    get public_market_stocks_heatmap_path

    assert_response :success
    assert_includes response.body, "embed-widget-stock-heatmap.js"
    assert_includes response.body, %Q(href="#{public_market_stocks_heatmap_path}")
    assert_includes response.body, %Q(href="#{public_market_stocks_news_path}")
    assert_not_includes response.body, %Q(href="#{new_session_path}")
    assert_not_includes response.body, %Q(href="#{market_stocks_path}")
  end

  test "should get public stocks news without signing in" do
    MarketNewsArticle.delete_all
    MarketNewsArticle.create!(
      source: "CNBC",
      title: "CNBC headline",
      translated_title: "CNBC 中文标题",
      url: "https://www.cnbc.com/example",
      published_at: Time.utc(2026, 4, 25, 8, 0, 0),
      fetched_at: Time.current
    )
    MarketNewsArticle.stubs(:refresh_if_stale!)

    get public_market_stocks_news_path(locale: "zh-CN")

    assert_response :success
    assert_includes response.body, "CNBC 中文标题"
    assert_includes response.body, %Q(href="#{public_market_stocks_heatmap_path}")
    assert_includes response.body, %Q(href="#{public_market_stocks_news_path}")
    assert_not_includes response.body, %Q(href="#{market_stocks_path}")
  end
end
