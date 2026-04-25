class PlaidAccount::Investments::HoldingsProcessor
  def initialize(plaid_account, security_resolver:)
    @plaid_account = plaid_account
    @security_resolver = security_resolver
  end

  def process
    processed_holding_keys = []
    processed_holding_dates = []

    holdings.each do |plaid_holding|
      resolved_security_result = security_resolver.resolve(plaid_security_id: plaid_holding["security_id"])

      # Skip brokerage cash and forex/cash-equivalent holdings
      next unless resolved_security_result.security.present?
      next if resolved_security_result.cash_equivalent?

      security = resolved_security_result.security
      holding_date = holding_date_for(plaid_holding)
      processed_holding_dates << holding_date
      processed_holding_keys << [ security.id, holding_date, plaid_holding["iso_currency_code"] ]

      ActiveRecord::Base.transaction do
        # Remove any duplicate rows and stale future holdings before upserting.
        # This must happen before save! to avoid unique constraint violations.
        account.holdings
          .where(security: security, date: holding_date, currency: plaid_holding["iso_currency_code"])
          .destroy_all

        # Delete all holdings for this security after the institution price date
        account.holdings
          .where(security: security)
          .where("date > ?", holding_date)
          .destroy_all

        holding = account.holdings.build(
          security: security,
          date: holding_date,
          currency: plaid_holding["iso_currency_code"],
          qty: plaid_holding["quantity"],
          price: plaid_holding["institution_price"],
          amount: plaid_holding["quantity"] * plaid_holding["institution_price"]
        )

        holding.save!
      end
    end

    snapshot_date = processed_holding_dates.max || Date.current
    upsert_zero_quantity_holdings_for_absent_securities(snapshot_date:, processed_holding_keys:)
  end

  private
    attr_reader :plaid_account, :security_resolver

    def account
      plaid_account.account
    end

    def holdings
      plaid_account.raw_investments_payload["holdings"] || []
    end

    def holding_date_for(plaid_holding)
      raw_date = plaid_holding["institution_price_as_of"]
      return Date.current if raw_date.blank?
      raw_date.is_a?(Date) ? raw_date : Date.parse(raw_date.to_s)
    end

    def upsert_zero_quantity_holdings_for_absent_securities(snapshot_date:, processed_holding_keys:)
      processed_key_map = processed_holding_keys.each_with_object({}) do |key, memo|
        memo[key] = true
      end

      latest_holdings_by_security_currency.each do |existing_holding|
        next if processed_key_map[[ existing_holding.security_id, snapshot_date, existing_holding.currency ]]

        zero_holding = account.holdings.find_or_initialize_by(
          security: existing_holding.security,
          date: snapshot_date,
          currency: existing_holding.currency
        )

        zero_holding.assign_attributes(
          qty: 0,
          price: existing_holding.price || 0,
          amount: 0
        )

        ActiveRecord::Base.transaction do
          zero_holding.save!

          account.holdings
            .where(security: existing_holding.security)
            .where("date > ?", snapshot_date)
            .destroy_all

          account.holdings
            .where(security: existing_holding.security, date: snapshot_date, currency: existing_holding.currency)
            .where.not(id: zero_holding.id)
            .destroy_all
        end
      end
    end

    def latest_holdings_by_security_currency
      account.holdings.where(
        id: account.holdings
          .select("DISTINCT ON (security_id, currency) id")
          .order(:security_id, :currency, date: :desc, created_at: :desc)
      )
    end
end
