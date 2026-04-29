require "test_helper"

class Account::InvestmentReportTest < ActiveSupport::TestCase
  setup do
    @plaid_account = plaid_accounts(:one)
    @account = accounts(:connected)

    @account.update!(
      accountable: Investment.new,
      accountable_type: "Investment",
      currency: "USD"
    )

    @plaid_account.update!(
      plaid_type: "investment",
      currency: "USD"
    )

    @account.entries.destroy_all
  end

  test "builds metrics and warnings from investment activity" do
    create_trade_entry("buy-1", "2026-04-02", "QQQM", 1, 250, 250)
    create_trade_entry("sell-1", "2026-04-03", "QQQM", -0.5, 260, -130)
    create_transaction_entry("dep-1", "2026-04-01", -1000, "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS")
    create_transaction_entry("div-1", "2026-04-04", -5, "QQQM(...) CASH DIVIDEND USD 0.5 PER SHARE (Ordinary Dividend)")
    create_transaction_entry("tax-1", "2026-04-04", 1, "QQQM(...) CASH DIVIDEND USD 0.5 PER SHARE - US TAX")
    create_transaction_entry("fx-1", "2026-04-05", 3900, "USD.HKD", currency: "HKD", kind: "funds_movement")

    @plaid_account.update!(raw_investments_payload: {
      "transactions" => [
        { "date" => "2026-04-02", "investment_transaction_id" => "buy-1", "type" => "buy", "name" => "QQQM", "amount" => 250, "iso_currency_code" => "USD", "fees" => -2 },
        { "date" => "2026-04-03", "investment_transaction_id" => "sell-1", "type" => "sell", "name" => "QQQM", "amount" => -130, "iso_currency_code" => "USD", "fees" => 0 },
        { "date" => "2026-04-01", "investment_transaction_id" => "dep-1", "type" => "cash", "name" => "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS", "amount" => 1000, "iso_currency_code" => "USD", "fees" => 0 },
        { "date" => "2026-04-04", "investment_transaction_id" => "div-1", "type" => "cash", "name" => "QQQM(...) CASH DIVIDEND USD 0.5 PER SHARE (Ordinary Dividend)", "amount" => -5, "iso_currency_code" => "USD", "fees" => 0 },
        { "date" => "2026-04-04", "investment_transaction_id" => "tax-1", "type" => "cash", "name" => "QQQM(...) CASH DIVIDEND USD 0.5 PER SHARE - US TAX", "amount" => 1, "iso_currency_code" => "USD", "fees" => 0 },
        { "date" => "2026-04-05", "investment_transaction_id" => "fx-1", "type" => "buy", "name" => "USD.HKD", "amount" => 3900, "iso_currency_code" => "HKD", "fees" => -1 }
      ]
    })

    report = Account::InvestmentReport.new(@account, period: Period.custom(start_date: Date.parse("2026-04-01"), end_date: Date.parse("2026-04-06")))

    assert_equal 6, report.metrics.size
    assert_equal %i[holdings activity reports], UI::AccountPage.new(account: @account).tabs
    assert_equal [ "QQQM" ], report.top_securities.map(&:ticker)
    assert_equal %w[buys sells deposits dividends taxes fx], report.breakdowns.map(&:id)
    assert_includes report.coverage_warnings.first, "Plaid only exposes one currency leg"
    assert_includes report.coverage_warnings.last, "settlement dates"
  end

  private
    def create_trade_entry(plaid_id, date, ticker, qty, price, amount)
      security = Security.find_or_create_by!(ticker: ticker) do |record|
        record.name = ticker
      end

      @account.entries.create!(
        plaid_id: plaid_id,
        date: Date.parse(date),
        amount: amount,
        currency: "USD",
        name: ticker,
        entryable: Trade.new(
          security: security,
          qty: qty,
          price: price,
          currency: "USD"
        )
      )
    end

    def create_transaction_entry(plaid_id, date, amount, name, currency: "USD", kind: "standard")
      @account.entries.create!(
        plaid_id: plaid_id,
        date: Date.parse(date),
        amount: amount,
        currency: currency,
        name: name,
        entryable: Transaction.new(kind: kind)
      )
    end
end
