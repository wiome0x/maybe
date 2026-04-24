require "test_helper"

class WeeklyReportBuilderTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:investment)
    @account.entries.destroy_all
  end

  test "builds overview and account sections for investment accounts" do
    create_trade_entry("weekly-buy", "2026-04-20", "NVDA", 1, 100, 100)
    create_transaction_entry("weekly-dep", "2026-04-21", -500, "CASH RECEIPTS / ELECTRONIC FUND TRANSFERS")

    period = Period.custom(start_date: Date.parse("2026-04-19"), end_date: Date.parse("2026-04-25"))
    payload = WeeklyReportBuilder.new(user: @user, period: period).build

    assert_equal @user.email, payload[:recipient_email]
    assert_equal 1, payload.dig(:overview, :account_count)
    assert payload.dig(:overview, :current_value).present?
    assert_equal @account.name, payload.dig(:accounts, 0, :name)
    assert payload.dig(:accounts, 0, :current_value).present?
    assert_equal "NVDA", payload.dig(:accounts, 0, :top_securities, 0, :ticker)
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
end
