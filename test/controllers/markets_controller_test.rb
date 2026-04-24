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

    get market_stocks_heatmap_path

    assert_response :success
    assert_includes response.body, "embed-widget-stock-heatmap.js"
    assert_includes response.body, "tradingview-widget-container"
    assert_includes response.body, "AAPL"
  end
end
