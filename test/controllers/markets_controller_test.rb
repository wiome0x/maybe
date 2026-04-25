require "test_helper"

class MarketsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    Rails.cache.clear
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
    assert_includes response.body, market_stocks_news_path
  end

  test "should get stocks news" do
    MarketNewsArticle.delete_all
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
    MarketNewsTranslator.stubs(:translate_items).returns([
      filtered_items.first.with(translated_title: "CNBC 中文标题"),
      filtered_items.last
    ])

    get market_stocks_news_path

    assert_response :success
    assert_includes response.body, "CNBC 中文标题"
    assert_includes response.body, "CNBC headline"
    assert_includes response.body, "Seeking Alpha headline"
    assert_includes response.body, "news_source=cnbc"
  end

  test "should filter stocks news by source" do
    MarketNewsArticle.delete_all
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

    get market_stocks_news_path(news_source: "cnbc")

    assert_response :success
    assert_includes response.body, "CNBC headline"
    assert_not_includes response.body, "Seeking Alpha headline"
  end

  test "should filter stocks news by sec source" do
    MarketNewsArticle.delete_all
    items = [
      MarketNewsFeed::Item.new(
        source: "SEC",
        title: "SEC enforcement headline",
        url: "https://www.sec.gov/example",
        published_at: Time.utc(2026, 4, 25, 6, 0, 0),
        translated_title: nil
      ),
      MarketNewsFeed::Item.new(
        source: "MarketWatch",
        title: "MarketWatch headline",
        url: "https://www.marketwatch.com/example",
        published_at: Time.utc(2026, 4, 25, 5, 30, 0),
        translated_title: nil
      )
    ]
    MarketNewsFeed.stubs(:fetch).returns(items)
    MarketNewsTranslator.stubs(:translate_items).returns(items.select { |item| item.source == "SEC" })

    get market_stocks_news_path(news_source: "sec")

    assert_response :success
    assert_includes response.body, "SEC enforcement headline"
    assert_not_includes response.body, "MarketWatch headline"
  end

  test "should return index quotes from stooq fallback when yahoo is unavailable" do
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_yahoo).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_eastmoney).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_nse).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_stooq).with do |symbols|
      symbols.include?("^DJI") && symbols.include?("^IXIC")
    end.returns({
      "^DJI" => { price: 49_230.7, change_percent: -0.16 },
      "^IXIC" => { price: 24_836.6, change_percent: 1.57 }
    })

    get market_indices_path(format: :json)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 49_230.7, body.dig("^DJI", "price")
    assert_equal(-0.16, body.dig("^DJI", "change_percent"))
    assert_equal 24_836.6, body.dig("^IXIC", "price")
  end

  test "should fall back to cached index quotes when live sources are empty" do
    Rails.cache.write(MarketsController::INDICES_CACHE_KEY, {
      "^DJI" => { price: 49_100.0, change_percent: 0.42 }
    }, expires_in: 10.minutes)

    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_yahoo).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_eastmoney).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_nse).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_stooq).returns({})

    get market_indices_path(format: :json)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 49_100.0, body.dig("^DJI", "price")
    assert_equal 0.42, body.dig("^DJI", "change_percent")
  end

  test "should return china index quotes from eastmoney fallback" do
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_yahoo).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_eastmoney).with do |symbols|
      symbols.include?("000001.SS") && symbols.include?("399001.SZ") && symbols.include?("899050.BJ")
    end.returns({
      "000001.SS" => { price: 4079.9, change_percent: -0.33 },
      "399001.SZ" => { price: 14_940.3, change_percent: -0.69 },
      "899050.BJ" => { price: 1370.22, change_percent: -0.57 }
    })
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_nse).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_stooq).returns({})

    get market_indices_path(format: :json)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 4079.9, body.dig("000001.SS", "price")
    assert_equal(-0.69, body.dig("399001.SZ", "change_percent"))
    assert_equal 1370.22, body.dig("899050.BJ", "price")
  end

  test "should return nifty quote from nse fallback" do
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_yahoo).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_eastmoney).returns({})
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_nse).with do |symbols|
      symbols.include?("^NSEI")
    end.returns({
      "^NSEI" => { price: 23_897.95, change_percent: -1.14 }
    })
    MarketsController.any_instance.stubs(:fetch_indices_quotes_from_stooq).returns({})

    get market_indices_path(format: :json)

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 23_897.95, body.dig("^NSEI", "price")
    assert_equal(-1.14, body.dig("^NSEI", "change_percent"))
  end
end
