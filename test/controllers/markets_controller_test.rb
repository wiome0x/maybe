require "test_helper"

class MarketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "should get stocks heatmap" do
    MarketsController.any_instance.stubs(:fetch_market_movers).returns([
      MarketQuote.new(
        symbol: "AAPL",
        name: "Apple",
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
    MarketNewsFeed.stubs(:fetch).returns([
      MarketNewsFeed::Item.new(
        source: "CNBC",
        title: "Stocks rally into the close",
        url: "https://www.cnbc.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: nil
      ),
      MarketNewsFeed::Item.new(
        source: "Seeking Alpha",
        title: "Apple shares rise after earnings",
        url: "https://seekingalpha.com/example",
        published_at: Time.utc(2026, 4, 25, 7, 30, 0),
        translated_title: nil
      )
    ])
    MarketNewsTranslator.stubs(:translate_items).returns([
      MarketNewsFeed::Item.new(
        source: "CNBC",
        title: "Stocks rally into the close",
        url: "https://www.cnbc.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: "美股收盘前走强"
      ),
      MarketNewsFeed::Item.new(
        source: "Seeking Alpha",
        title: "Apple shares rise after earnings",
        url: "https://seekingalpha.com/example",
        published_at: Time.utc(2026, 4, 25, 7, 30, 0),
        translated_title: nil
      )
    ])

    get market_stocks_heatmap_path

    assert_response :success
    assert_includes response.body, "embed-widget-stock-heatmap.js"
    assert_includes response.body, "tradingview-widget-container"
    assert_includes response.body, "AAPL"
    assert_includes response.body, "Stocks rally into the close"
    assert_includes response.body, "美股收盘前走强"
    assert_includes response.body, "CNBC"
    assert_includes response.body, "Seeking Alpha"
    assert_includes response.body, "news_source=cnbc"
  end

  test "should filter stocks heatmap news by source" do
    MarketsController.any_instance.stubs(:fetch_market_movers).returns([])
    filtered_items = [
      MarketNewsFeed::Item.new(
        source: "CNBC",
        title: "CNBC headline",
        url: "https://www.cnbc.com/example",
        published_at: Time.utc(2026, 4, 25, 8, 0, 0),
        translated_title: nil
      ),
      MarketNewsFeed::Item.new(
        source: "Seeking Alpha",
        title: "Seeking Alpha headline",
        url: "https://seekingalpha.com/example",
        published_at: Time.utc(2026, 4, 25, 7, 30, 0),
        translated_title: nil
      )
    ]
    MarketNewsFeed.stubs(:fetch).returns(filtered_items)
    MarketNewsTranslator.stubs(:translate_items).returns(filtered_items.select { |item| item.source == "CNBC" })

    get market_stocks_heatmap_path(news_source: "cnbc")

    assert_response :success
    assert_includes response.body, "CNBC headline"
    assert_not_includes response.body, "Seeking Alpha headline"
  end
end
