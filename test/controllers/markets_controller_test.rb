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
        published_at: Time.utc(2026, 4, 25, 8, 0, 0)
      )
    ])

    get market_stocks_heatmap_path

    assert_response :success
    assert_includes response.body, "embed-widget-stock-heatmap.js"
    assert_includes response.body, "tradingview-widget-container"
    assert_includes response.body, "AAPL"
    assert_includes response.body, "Stocks rally into the close"
    assert_includes response.body, "CNBC"
  end
end
