require "test_helper"

class WeeklyReportBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:investment)
    @account.entries.destroy_all
  end

  test "builds overview and account sections for investment accounts" do
    create_trade_entry("weekly-buy", "2026-04-20", "NVDA", 1, 100, 100)
    create_current_holding("NVDA", qty: 2, price: 150, amount: 300)
    create_transaction_entry("weekly-dep", "2026-04-21", -500, "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS")
    plaid_item = @user.family.plaid_items.create!(plaid_id: "item_weekly_report_builder", name: "IBKR", access_token: "test-token")
    plaid_account = PlaidAccount.create!(
      plaid_id: "acc_weekly_report_builder",
      current_balance: 1000,
      available_balance: 1000,
      currency: "USD",
      name: "Named Brokerage",
      plaid_type: "investment",
      plaid_subtype: "brokerage",
      plaid_item: plaid_item
    )
    @account.update!(plaid_account: plaid_account)

    period = Period.custom(start_date: Date.parse("2026-04-19"), end_date: Date.parse("2026-04-25"))
    payload = WeeklyReportBuilder.new(user: @user, period: period).build

    assert_equal @user.email, payload[:recipient_email]
    assert_equal 1, payload.dig(:overview, :account_count)
    assert payload.dig(:overview, :current_value).present?
    assert_equal "IBKR", payload.dig(:accounts, 0, :name)
    assert_equal @account.name, payload.dig(:accounts, 0, :account_label)
    assert payload.dig(:accounts, 0, :current_value).present?
    assert payload.dig(:accounts, 0, :top_holdings).present?
    assert_includes payload.dig(:accounts, 0, :top_holdings).map { |row| row[:ticker] }, "NVDA"
    assert payload.dig(:accounts, 0, :top_holdings, 0, :amount).present?
    assert payload.dig(:accounts, 0, :top_holdings, 0, :weight).present?
    assert payload.dig(:overview, :balance_series).present?
    assert payload.dig(:overview, :multi_balance_series, :series).present?
    assert_equal "total", payload.dig(:overview, :multi_balance_series, :series, 0, :id)
    assert payload.dig(:overview, :account_value_breakdown).present?
    assert payload.dig(:accounts, 0, :balance_chart_data).present?
    assert payload.dig(:accounts, 0, :chart_color).present?
    assert_nil payload.dig(:overview, :contribution_series)
    assert_nil payload.dig(:accounts, 0, :contribution_series)
  end

  test "returns empty account sections when user has no investment accounts" do
    @user.family.accounts.where(accountable_type: "Investment").destroy_all

    payload = WeeklyReportBuilder.new(user: @user, period: Period.last_7_days).build

    assert_equal 0, payload.dig(:overview, :account_count)
    assert_equal [], payload[:accounts]
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

    def create_current_holding(ticker, qty:, price:, amount:, currency: "USD")
      security = Security.find_or_create_by!(ticker: ticker) do |record|
        record.name = ticker
      end

      @account.holdings.create!(
        security: security,
        date: Date.current,
        qty: qty,
        price: price,
        amount: amount,
        currency: currency
      )
    end
end
