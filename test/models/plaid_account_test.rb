require "test_helper"
require "ostruct"

class PlaidAccountTest < ActiveSupport::TestCase
  test "uses unofficial currency code when iso currency code is unavailable" do
    plaid_account = plaid_accounts(:one)

    account_snapshot = OpenStruct.new(
      balances: OpenStruct.new(
        current: 1000,
        available: 900,
        iso_currency_code: nil,
        unofficial_currency_code: "BTC"
      ),
      type: "depository",
      subtype: "checking",
      name: "Test Account",
      mask: "1234"
    )

    plaid_account.upsert_plaid_snapshot!(account_snapshot)

    assert_equal "BTC", plaid_account.reload.currency
  end
end
