require "test_helper"

class PlaidAccount::Investments::TransactionsProcessorTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @security_resolver = PlaidAccount::Investments::SecurityResolver.new(@plaid_account)
  end

  test "creates regular trade entries" do
    test_investments_payload = {
      transactions: [
        {
          "transaction_id" => "123",
          "security_id" => "123",
          "type" => "buy",
          "quantity" => 1, # Positive, so "buy 1 share"
          "price" => 100,
          "amount" => 100,
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "Buy 1 share of AAPL"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.stubs(:resolve).returns(OpenStruct.new(
      security: securities(:aapl)
    ))

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Trade.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal 100, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Buy 1 share of AAPL", entry.name
  end

  test "creates cash transactions" do
    test_investments_payload = {
      transactions: [
        {
          "transaction_id" => "123",
          "type" => "cash",
          "subtype" => "withdrawal",
          "amount" => 100, # Positive, so moving money OUT of the account
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "Withdrawal"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).never # Cash transactions don't have a security

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal 100, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Withdrawal", entry.name
  end

  test "normalizes cash receipts marked as withdrawal to inflow sign" do
    test_investments_payload = {
      transactions: [
        {
          "investment_transaction_id" => "cash-receipt-1",
          "type" => "cash",
          "subtype" => "withdrawal",
          "amount" => 10_000.0,
          "iso_currency_code" => "HKD",
          "date" => Date.current,
          "name" => "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).never

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal(-10_000.0, entry.amount.to_f)
    assert_equal "HKD", entry.currency
    assert_equal "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS", entry.name
  end

  test "creates fee transactions" do
    test_investments_payload = {
      transactions: [
        {
          "transaction_id" => "123",
          "type" => "fee",
          "subtype" => "miscellaneous fee",
          "amount" => 10.25,
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "Miscellaneous fee"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).never # Cash transactions don't have a security

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal 10.25, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Miscellaneous fee", entry.name
  end

  test "handles bad plaid quantity signage data" do
    test_investments_payload = {
      transactions: [
        {
          "transaction_id" => "123",
          "type" => "sell", # Correct type
          "subtype" => "sell", # Correct subtype
          "quantity" => 1, # ***Incorrect signage***, this should be negative
          "price" => 100, # Correct price
          "amount" => -100, # Correct amount
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "Sell 1 share of AAPL"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).returns(OpenStruct.new(
      security: securities(:aapl)
    ))

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Trade.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal -100, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Sell 1 share of AAPL", entry.name

    assert_equal -1, entry.trade.qty
  end

  test "creates transfer transactions as cash transactions" do
    test_investments_payload = {
      transactions: [
        {
          "investment_transaction_id" => "123",
          "type" => "transfer",
          "amount" => -100.0,
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "Bank Transfer"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).never

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      processor.process
    end

    entry = Entry.order(created_at: :desc).first

    assert_equal -100.0, entry.amount
    assert_equal "USD", entry.currency
    assert_equal Date.current, entry.date
    assert_equal "Bank Transfer", entry.name
    assert_instance_of Transaction, entry.entryable
  end

  test "does not create entries for forex cash-equivalent conversion trades" do
    test_investments_payload = {
      transactions: [
        {
          "investment_transaction_id" => "fx-1",
          "security_id" => "forex-security",
          "type" => "buy",
          "amount" => 30_000.0,
          "iso_currency_code" => "HKD",
          "date" => Date.current,
          "name" => "USD.HKD"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).returns(OpenStruct.new(
      security: nil,
      cash_equivalent?: true,
      brokerage_cash?: false
    ))

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_no_difference [ "Entry.count", "Transaction.count", "Trade.count" ] do
      processor.process
    end
  end

  test "creates cash entries for brokerage cash-equivalent transactions" do
    test_investments_payload = {
      transactions: [
        {
          "investment_transaction_id" => "cash-1",
          "security_id" => "brokerage-cash-security",
          "type" => "buy",
          "amount" => 100.0,
          "iso_currency_code" => "USD",
          "date" => Date.current,
          "name" => "CUR:USD"
        }
      ]
    }

    @plaid_account.update!(raw_investments_payload: test_investments_payload)

    @security_resolver.expects(:resolve).returns(OpenStruct.new(
      security: nil,
      cash_equivalent?: true,
      brokerage_cash?: true
    ))

    processor = PlaidAccount::Investments::TransactionsProcessor.new(@plaid_account, security_resolver: @security_resolver)

    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      processor.process
    end
  end
end
