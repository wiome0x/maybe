require "test_helper"

class Family::DataExporterTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @other_family = families(:empty)
    @exporter = Family::DataExporter.new(@family)

    # Create some test data for the family
    @account = @family.accounts.create!(
      name: "Test Account",
      accountable: Depository.new,
      balance: 1000,
      currency: "USD"
    )

    @category = @family.categories.create!(
      name: "Test Category",
      color: "#FF0000"
    )

    @tag = @family.tags.create!(
      name: "Test Tag",
      color: "#00FF00"
    )

    @security = Security.create!(
      ticker: "TEST",
      name: "Test Security",
      exchange_operating_mic: "XNAS"
    )

    @holding = @account.holdings.create!(
      security: @security,
      date: Date.current,
      qty: 2,
      price: 50,
      amount: 100,
      currency: "USD"
    )

    @balance = @account.balances.create!(
      date: Date.current,
      currency: "USD",
      balance: 1000,
      cash_balance: 400,
      start_balance: 900,
      start_cash_balance: 300,
      start_non_cash_balance: 600,
      cash_inflows: 50,
      cash_outflows: 10,
      non_cash_inflows: 70,
      non_cash_outflows: 20,
      net_market_flows: 10,
      cash_adjustments: 0,
      non_cash_adjustments: 0,
      end_balance: 1000,
      end_cash_balance: 400,
      end_non_cash_balance: 600,
      flows_factor: 1
    )

    @watchlist_item = @family.watchlist_items.create!(
      symbol: "TEST",
      name: "Test Security",
      item_type: "stock",
      position: 1
    )

    @rule = @family.rules.create!(
      name: "Test Rule",
      resource_type: "transaction",
      conditions_attributes: [
        {
          condition_type: "name",
          operator: "contains",
          value: "dividend"
        }
      ],
      actions_attributes: [
        {
          action_type: "set_transaction_name",
          value: "Normalized dividend"
        }
      ]
    )
  end

  test "generates a zip file with all required files" do
    zip_data = @exporter.generate_export

    assert zip_data.is_a?(StringIO)

    # Check that the zip contains all expected files
    expected_files = [
      "family.csv",
      "accounts.csv",
      "balances.csv",
      "holdings.csv",
      "securities.csv",
      "transactions.csv",
      "trades.csv",
      "categories.csv",
      "watchlist_items.csv",
      "all.ndjson"
    ]

    Zip::File.open_buffer(zip_data) do |zip|
      actual_files = zip.entries.map(&:name)
      assert_equal expected_files.sort, actual_files.sort
    end
  end

  test "generates valid CSV files" do
    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      # Check accounts.csv
      accounts_csv = zip.read("accounts.csv")
      assert accounts_csv.include?("id,name,type,subtype,balance,currency,created_at")

      # Check family.csv
      family_csv = zip.read("family.csv")
      assert family_csv.include?("id,name,currency,locale,timezone,date_format,country,auto_sync_on_login,data_enrichment_enabled,trend_color_preference,created_at,updated_at")

      # Check balances.csv
      balances_csv = zip.read("balances.csv")
      assert balances_csv.include?("id,account_id,account_name,date,currency,balance,cash_balance,start_balance,start_cash_balance,start_non_cash_balance,cash_inflows,cash_outflows,non_cash_inflows,non_cash_outflows,net_market_flows,cash_adjustments,non_cash_adjustments,end_balance,end_cash_balance,end_non_cash_balance,flows_factor,created_at,updated_at")

      # Check holdings.csv
      holdings_csv = zip.read("holdings.csv")
      assert holdings_csv.include?("id,account_id,account_name,security_id,ticker,name,date,qty,price,amount,currency,created_at,updated_at")

      # Check securities.csv
      securities_csv = zip.read("securities.csv")
      assert securities_csv.include?("id,ticker,name,exchange_operating_mic,exchange_mic,exchange_acronym,country_code,logo_url,offline,created_at,updated_at")

      # Check transactions.csv
      transactions_csv = zip.read("transactions.csv")
      assert transactions_csv.include?("date,account_name,amount,name,category,tags,notes,currency")

      # Check trades.csv
      trades_csv = zip.read("trades.csv")
      assert trades_csv.include?("date,account_name,ticker,quantity,price,amount,currency")

      # Check categories.csv
      categories_csv = zip.read("categories.csv")
      assert categories_csv.include?("name,color,parent_category,classification")

      # Check watchlist_items.csv
      watchlist_items_csv = zip.read("watchlist_items.csv")
      assert watchlist_items_csv.include?("id,symbol,name,item_type,position,created_at,updated_at")
    end
  end

  test "generates valid NDJSON file" do
    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      ndjson_content = zip.read("all.ndjson")
      lines = ndjson_content.split("\n")

      lines.each do |line|
        assert_nothing_raised { JSON.parse(line) }
      end

      # Check that each line has expected structure
      first_line = JSON.parse(lines.first)
      assert first_line.key?("type")
      assert first_line.key?("data")

      types = lines.map { |line| JSON.parse(line).fetch("type") }.uniq
      assert_includes types, "Family"
      assert_includes types, "Balance"
      assert_includes types, "Holding"
      assert_includes types, "Security"
      assert_includes types, "Rule"
      assert_includes types, "WatchlistItem"
    end
  end

  test "only exports data from the specified family" do
    # Create data for another family that should NOT be exported
    other_account = @other_family.accounts.create!(
      name: "Other Family Account",
      accountable: Depository.new,
      balance: 5000,
      currency: "USD"
    )

    other_category = @other_family.categories.create!(
      name: "Other Family Category",
      color: "#0000FF"
    )

    other_watchlist_item = @other_family.watchlist_items.create!(
      symbol: "OTHER",
      name: "Other Security",
      item_type: "stock",
      position: 1
    )

    zip_data = @exporter.generate_export

    Zip::File.open_buffer(zip_data) do |zip|
      # Check accounts.csv doesn't contain other family's data
      accounts_csv = zip.read("accounts.csv")
      assert accounts_csv.include?(@account.name)
      refute accounts_csv.include?(other_account.name)

      # Check categories.csv doesn't contain other family's data
      categories_csv = zip.read("categories.csv")
      assert categories_csv.include?(@category.name)
      refute categories_csv.include?(other_category.name)

      watchlist_items_csv = zip.read("watchlist_items.csv")
      assert watchlist_items_csv.include?(@watchlist_item.symbol)
      refute watchlist_items_csv.include?(other_watchlist_item.symbol)

      # Check NDJSON doesn't contain other family's data
      ndjson_content = zip.read("all.ndjson")
      refute ndjson_content.include?(other_account.id)
      refute ndjson_content.include?(other_category.id)
      refute ndjson_content.include?(other_watchlist_item.id)
    end
  end
end
