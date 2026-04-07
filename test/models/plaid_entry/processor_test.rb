require "test_helper"

class PlaidEntry::ProcessorTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @category_matcher = mock("PlaidAccount::Transactions::CategoryMatcher")
  end

  test "creates new entry transaction" do
    plaid_transaction = {
      "transaction_id" => "123",
      "merchant_name" => "Amazon", # this is used for merchant and entry name
      "amount" => 100,
      "date" => Date.current,
      "iso_currency_code" => "USD",
      "personal_finance_category" => {
        "detailed" => "Food"
      },
      "merchant_entity_id" => "123"
    }

    @category_matcher.expects(:match).with("Food").returns(categories(:food_and_drink))

    processor = PlaidEntry::Processor.new(
      plaid_transaction,
      plaid_account: @plaid_account,
      category_matcher: @category_matcher
    )

    assert_difference [ "Entry.count", "Transaction.count", "ProviderMerchant.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal 100, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Amazon", entry.name
    assert_equal categories(:food_and_drink).id, entry.transaction.category_id

    provider_merchant = ProviderMerchant.order(created_at: :desc).first

    assert_equal "Amazon", provider_merchant.name
  end

  test "updates existing entry transaction" do
    existing_plaid_id = "existing_plaid_id"

    plaid_transaction = {
      "transaction_id" => existing_plaid_id,
      "merchant_name" => "Amazon", # this is used for merchant and entry name
      "amount" => 200, # Changed amount will be updated
      "date" => 1.day.ago.to_date, # Changed date will be updated
      "iso_currency_code" => "USD",
      "personal_finance_category" => {
        "detailed" => "Food"
      }
    }

    @category_matcher.expects(:match).with("Food").returns(categories(:food_and_drink))

    # Create an existing entry
    @plaid_account.account.entries.create!(
      plaid_id: existing_plaid_id,
      amount: 100,
      currency: "USD",
      date: Date.current,
      name: "Amazon",
      entryable: Transaction.new
    )

    processor = PlaidEntry::Processor.new(
      plaid_transaction,
      plaid_account: @plaid_account,
      category_matcher: @category_matcher
    )

    assert_no_difference [ "Entry.count", "Transaction.count", "ProviderMerchant.count" ] do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal 200, entry.amount
    assert_equal "USD", entry.currency
    assert_equal 1.day.ago.to_date, entry.date
    assert_equal "Amazon", entry.name
    assert_equal categories(:food_and_drink).id, entry.transaction.category_id
  end

  test "uses unofficial currency code when iso currency code is missing" do
    plaid_transaction = {
      "transaction_id" => "tx_unofficial_currency",
      "merchant_name" => "Amazon",
      "amount" => 50,
      "date" => Date.current,
      "unofficial_currency_code" => "BTC"
    }

    processor = PlaidEntry::Processor.new(
      plaid_transaction,
      plaid_account: @plaid_account,
      category_matcher: @category_matcher
    )

    processor.process

    entry = Entry.find_by!(plaid_id: "tx_unofficial_currency")
    assert_equal "BTC", entry.currency
  end

  test "falls back to account currency when plaid transaction has no currency fields" do
    plaid_transaction = {
      "transaction_id" => "tx_missing_currency",
      "merchant_name" => "Amazon",
      "amount" => 25,
      "date" => Date.current
    }

    processor = PlaidEntry::Processor.new(
      plaid_transaction,
      plaid_account: @plaid_account,
      category_matcher: @category_matcher
    )

    processor.process

    entry = Entry.find_by!(plaid_id: "tx_missing_currency")
    assert_equal @plaid_account.account.currency, entry.currency
  end
end
