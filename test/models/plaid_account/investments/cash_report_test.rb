require "test_helper"

class PlaidAccount::Investments::CashReportTest < ActiveSupport::TestCase
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

  test "summarizes per-currency cash report lines from plaid investment transactions" do
    @plaid_account.update!(raw_investments_payload: {
      "transactions" => [
        {
          "date" => "2026-04-02",
          "investment_transaction_id" => "dep-1",
          "type" => "cash",
          "name" => "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS",
          "amount" => 1000,
          "iso_currency_code" => "USD",
          "fees" => 0
        },
        {
          "date" => "2026-04-03",
          "investment_transaction_id" => "div-1",
          "type" => "cash",
          "name" => "VOO(...) CASH DIVIDEND USD 1.23 PER SHARE (Ordinary Dividend)",
          "amount" => -5,
          "iso_currency_code" => "USD",
          "fees" => 0
        },
        {
          "date" => "2026-04-03",
          "investment_transaction_id" => "tax-1",
          "type" => "cash",
          "name" => "VOO(...) CASH DIVIDEND USD 1.23 PER SHARE - US TAX",
          "amount" => 1,
          "iso_currency_code" => "USD",
          "fees" => 0
        },
        {
          "date" => "2026-04-04",
          "investment_transaction_id" => "buy-1",
          "type" => "buy",
          "name" => "VANGUARD S&P 500 ETF",
          "amount" => 200,
          "iso_currency_code" => "USD",
          "fees" => -2.5
        },
        {
          "date" => "2026-04-05",
          "investment_transaction_id" => "sell-1",
          "type" => "sell",
          "name" => "TESLA INC",
          "amount" => -120,
          "iso_currency_code" => "USD",
          "fees" => 0
        }
      ]
    })

    create_transaction_entry("dep-1", date: "2026-04-02", amount: -1000, currency: "USD", name: "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS")
    create_transaction_entry("div-1", date: "2026-04-03", amount: -5, currency: "USD", name: "Dividend")
    create_transaction_entry("tax-1", date: "2026-04-03", amount: 1, currency: "USD", name: "Withholding tax")
    create_transaction_entry("buy-1", date: "2026-04-04", amount: 200, currency: "USD", name: "Buy VOO")
    create_transaction_entry("sell-1", date: "2026-04-05", amount: -120, currency: "USD", name: "Sell TSLA")

    summary = PlaidAccount::Investments::CashReport
      .new(@account, start_date: Date.parse("2026-04-01"), end_date: Date.parse("2026-04-30"))

    assert summary.exact?

    usd_summary = summary.per_currency.fetch("USD")

    assert_equal BigDecimal("0"), usd_summary.opening_cash
    assert_equal BigDecimal("-2.5"), usd_summary.commissions
    assert_equal BigDecimal("1000"), usd_summary.deposits_withdrawals
    assert_equal BigDecimal("5"), usd_summary.dividends
    assert_equal BigDecimal("120"), usd_summary.trade_sells
    assert_equal BigDecimal("-200"), usd_summary.trade_buys
    assert_equal BigDecimal("-1"), usd_summary.withholding_tax
    assert_equal BigDecimal("921.5"), usd_summary.ending_cash
  end

  test "computes base-currency FX translation residual from mixed-currency cash flows" do
    ExchangeRate.create!(
      from_currency: "HKD",
      to_currency: "USD",
      rate: BigDecimal("0.125"),
      date: Date.parse("2026-04-02")
    )

    ExchangeRate.create!(
      from_currency: "HKD",
      to_currency: "USD",
      rate: BigDecimal("0.13"),
      date: Date.parse("2026-04-30")
    )

    @plaid_account.update!(raw_investments_payload: {
      "transactions" => [
        {
          "date" => "2026-04-02",
          "investment_transaction_id" => "hkd-dep-1",
          "type" => "cash",
          "name" => "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS",
          "amount" => 1000,
          "iso_currency_code" => "HKD",
          "fees" => 0
        }
      ]
    })

    create_transaction_entry("hkd-dep-1", date: "2026-04-02", amount: -1000, currency: "HKD", name: "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS")

    summary = PlaidAccount::Investments::CashReport
      .new(@account, start_date: Date.parse("2026-04-01"), end_date: Date.parse("2026-04-30"))
      .base_currency_summary

    assert_equal BigDecimal("0"), summary.opening_cash
    assert_equal BigDecimal("125"), summary.deposits_withdrawals
    assert_equal BigDecimal("130"), summary.ending_cash
    assert_equal BigDecimal("5"), summary.fx_translation_gain_loss
  end

  test "marks report as inexact when forex transactions only expose one leg" do
    @plaid_account.update!(raw_investments_payload: {
      "transactions" => [
        {
          "date" => "2026-04-02",
          "investment_transaction_id" => "fx-1",
          "type" => "buy",
          "name" => "USD.HKD",
          "amount" => 3900,
          "iso_currency_code" => "HKD",
          "fees" => -2
        }
      ]
    })

    create_transaction_entry("fx-1", date: "2026-04-02", amount: 3900, currency: "HKD", name: "USD.HKD")

    report = PlaidAccount::Investments::CashReport
      .new(@account, start_date: Date.parse("2026-04-01"), end_date: Date.parse("2026-04-30"))

    assert_not report.exact?
    assert_includes report.unsupported_reasons, :missing_forex_counterparty_legs
    assert_includes report.unsupported_reasons, :missing_settlement_dates
  end

  private
    def create_transaction_entry(plaid_id, date:, amount:, currency:, name:)
      @account.entries.create!(
        plaid_id: plaid_id,
        date: Date.parse(date),
        amount: amount,
        currency: currency,
        name: name,
        entryable: Transaction.new
      )
    end
end
