require "zip"
require "csv"

class Family::DataExporter
  def initialize(family)
    @family = family
  end

  def generate_export
    zip_data = Zip::OutputStream.write_buffer do |zipfile|
      write_zip_entry(zipfile, "family.csv", generate_family_csv)
      write_zip_entry(zipfile, "accounts.csv", generate_accounts_csv)
      write_zip_entry(zipfile, "balances.csv", generate_balances_csv)
      write_zip_entry(zipfile, "holdings.csv", generate_holdings_csv)
      write_zip_entry(zipfile, "securities.csv", generate_securities_csv)
      write_zip_entry(zipfile, "transactions.csv", generate_transactions_csv)
      write_zip_entry(zipfile, "trades.csv", generate_trades_csv)
      write_zip_entry(zipfile, "categories.csv", generate_categories_csv)
      write_zip_entry(zipfile, "watchlist_items.csv", generate_watchlist_items_csv)
      write_zip_entry(zipfile, "all.ndjson", generate_ndjson)
    end

    zip_data.rewind
    zip_data
  end

  private

    def write_zip_entry(zipfile, filename, content)
      zipfile.put_next_entry(filename)
      zipfile.write(content)
    end

    def generate_family_csv
      CSV.generate do |csv|
        csv << [ "id", "name", "currency", "locale", "timezone", "date_format", "country", "auto_sync_on_login", "data_enrichment_enabled", "trend_color_preference", "created_at", "updated_at" ]
        csv << [
          @family.id,
          @family.name,
          @family.currency,
          @family.locale,
          @family.timezone,
          @family.date_format,
          @family.country,
          @family.auto_sync_on_login,
          @family.data_enrichment_enabled,
          @family.trend_color_preference,
          @family.created_at.iso8601,
          @family.updated_at.iso8601
        ]
      end
    end

    def generate_accounts_csv
      CSV.generate do |csv|
        csv << [ "id", "name", "type", "subtype", "balance", "currency", "created_at" ]

        @family.accounts.includes(:accountable).find_each do |account|
          csv << [
            account.id,
            account.name,
            account.accountable_type,
            account.subtype,
            account.balance.to_s,
            account.currency,
            account.created_at.iso8601
          ]
        end
      end
    end

    def generate_balances_csv
      CSV.generate do |csv|
        csv << [ "id", "account_id", "account_name", "date", "currency", "balance", "cash_balance", "start_balance", "start_cash_balance", "start_non_cash_balance", "cash_inflows", "cash_outflows", "non_cash_inflows", "non_cash_outflows", "net_market_flows", "cash_adjustments", "non_cash_adjustments", "end_balance", "end_cash_balance", "end_non_cash_balance", "flows_factor", "created_at", "updated_at" ]

        @family.accounts.includes(:balances).find_each do |account|
          account.balances.chronological.each do |balance|
            csv << [
              balance.id,
              account.id,
              account.name,
              balance.date.iso8601,
              balance.currency,
              balance.balance.to_s,
              balance.cash_balance.to_s,
              balance.start_balance.to_s,
              balance.start_cash_balance.to_s,
              balance.start_non_cash_balance.to_s,
              balance.cash_inflows.to_s,
              balance.cash_outflows.to_s,
              balance.non_cash_inflows.to_s,
              balance.non_cash_outflows.to_s,
              balance.net_market_flows.to_s,
              balance.cash_adjustments.to_s,
              balance.non_cash_adjustments.to_s,
              balance.end_balance.to_s,
              balance.end_cash_balance.to_s,
              balance.end_non_cash_balance.to_s,
              balance.flows_factor,
              balance.created_at.iso8601,
              balance.updated_at.iso8601
            ]
          end
        end
      end
    end

    def generate_holdings_csv
      CSV.generate do |csv|
        csv << [ "id", "account_id", "account_name", "security_id", "ticker", "name", "date", "qty", "price", "amount", "currency", "created_at", "updated_at" ]

        @family.holdings.includes(:account, :security).chronological.find_each do |holding|
          csv << [
            holding.id,
            holding.account_id,
            holding.account.name,
            holding.security_id,
            holding.ticker,
            holding.name,
            holding.date.iso8601,
            holding.qty.to_s,
            holding.price.to_s,
            holding.amount.to_s,
            holding.currency,
            holding.created_at.iso8601,
            holding.updated_at.iso8601
          ]
        end
      end
    end

    def generate_securities_csv
      CSV.generate do |csv|
        csv << [ "id", "ticker", "name", "exchange_operating_mic", "exchange_mic", "exchange_acronym", "country_code", "logo_url", "offline", "created_at", "updated_at" ]

        family_securities_scope.find_each do |security|
          csv << [
            security.id,
            security.ticker,
            security.name,
            security.exchange_operating_mic,
            security.exchange_mic,
            security.exchange_acronym,
            security.country_code,
            security.logo_url,
            security.offline,
            security.created_at.iso8601,
            security.updated_at.iso8601
          ]
        end
      end
    end

    def generate_transactions_csv
      CSV.generate do |csv|
        csv << [ "date", "account_name", "amount", "name", "category", "tags", "notes", "currency" ]

        @family.transactions
          .includes(:category, :tags, entry: :account)
          .find_each do |transaction|
            csv << [
              transaction.entry.date.iso8601,
              transaction.entry.account.name,
              transaction.entry.amount.to_s,
              transaction.entry.name,
              transaction.category&.name,
              transaction.tags.pluck(:name).join(","),
              transaction.entry.notes,
              transaction.entry.currency
            ]
        end
      end
    end

    def generate_trades_csv
      CSV.generate do |csv|
        csv << [ "date", "account_name", "ticker", "quantity", "price", "amount", "currency" ]

        @family.trades
          .includes(:security, entry: :account)
          .find_each do |trade|
            csv << [
              trade.entry.date.iso8601,
              trade.entry.account.name,
              trade.security.ticker,
              trade.qty.to_s,
              trade.price.to_s,
              trade.entry.amount.to_s,
              trade.currency
            ]
        end
      end
    end

    def generate_categories_csv
      CSV.generate do |csv|
        csv << [ "name", "color", "parent_category", "classification" ]

        @family.categories.includes(:parent).find_each do |category|
          csv << [
            category.name,
            category.color,
            category.parent&.name,
            category.classification
          ]
        end
      end
    end

    def generate_watchlist_items_csv
      CSV.generate do |csv|
        csv << [ "id", "symbol", "name", "item_type", "position", "created_at", "updated_at" ]

        @family.watchlist_items.ordered.find_each do |item|
          csv << [
            item.id,
            item.symbol,
            item.name,
            item.item_type,
            item.position,
            item.created_at.iso8601,
            item.updated_at.iso8601
          ]
        end
      end
    end

    def generate_ndjson
      lines = []

      lines << {
        type: "Family",
        data: @family.as_json
      }.to_json

      @family.accounts.includes(:accountable).find_each do |account|
        lines << {
          type: "Account",
          data: account.as_json(
            include: {
              accountable: {}
            }
          )
        }.to_json
      end

      @family.accounts.includes(:balances).find_each do |account|
        account.balances.chronological.each do |balance|
          lines << {
            type: "Balance",
            data: balance.as_json
          }.to_json
        end
      end

      family_securities_scope.find_each do |security|
        lines << {
          type: "Security",
          data: security.as_json
        }.to_json
      end

      @family.holdings.includes(:security).chronological.find_each do |holding|
        lines << {
          type: "Holding",
          data: holding.as_json.merge(
            "ticker" => holding.ticker,
            "security_name" => holding.name
          )
        }.to_json
      end

      @family.categories.find_each do |category|
        lines << {
          type: "Category",
          data: category.as_json
        }.to_json
      end

      # Export tags
      @family.tags.find_each do |tag|
        lines << {
          type: "Tag",
          data: tag.as_json
        }.to_json
      end

      @family.merchants.find_each do |merchant|
        lines << {
          type: "Merchant",
          data: merchant.as_json
        }.to_json
      end

      @family.transactions.includes(:category, :merchant, :tags, entry: :account).find_each do |transaction|
        lines << {
          type: "Transaction",
          data: {
            id: transaction.id,
            entry_id: transaction.entry.id,
            account_id: transaction.entry.account_id,
            date: transaction.entry.date,
            amount: transaction.entry.amount,
            currency: transaction.entry.currency,
            name: transaction.entry.name,
            notes: transaction.entry.notes,
            excluded: transaction.entry.excluded,
            category_id: transaction.category_id,
            merchant_id: transaction.merchant_id,
            tag_ids: transaction.tag_ids,
            kind: transaction.kind,
            created_at: transaction.created_at,
            updated_at: transaction.updated_at
          }
        }.to_json
      end

      @family.trades.includes(:security, entry: :account).find_each do |trade|
        lines << {
          type: "Trade",
          data: {
            id: trade.id,
            entry_id: trade.entry.id,
            account_id: trade.entry.account_id,
            security_id: trade.security_id,
            ticker: trade.security.ticker,
            date: trade.entry.date,
            qty: trade.qty,
            price: trade.price,
            amount: trade.entry.amount,
            currency: trade.currency,
            created_at: trade.created_at,
            updated_at: trade.updated_at
          }
        }.to_json
      end

      @family.entries.valuations.includes(:account, :entryable).find_each do |entry|
        lines << {
          type: "Valuation",
          data: {
            id: entry.entryable.id,
            entry_id: entry.id,
            account_id: entry.account_id,
            date: entry.date,
            amount: entry.amount,
            currency: entry.currency,
            name: entry.name,
            created_at: entry.created_at,
            updated_at: entry.updated_at
          }
        }.to_json
      end

      @family.budgets.find_each do |budget|
        lines << {
          type: "Budget",
          data: budget.as_json
        }.to_json
      end

      @family.budget_categories.includes(:budget, :category).find_each do |budget_category|
        lines << {
          type: "BudgetCategory",
          data: budget_category.as_json
        }.to_json
      end

      @family.rules.includes(conditions: :sub_conditions, actions: {}).find_each do |rule|
        lines << {
          type: "Rule",
          data: rule.as_json(
            include: {
              conditions: {
                include: {
                  sub_conditions: {}
                }
              },
              actions: {}
            }
          )
        }.to_json
      end

      @family.watchlist_items.ordered.find_each do |item|
        lines << {
          type: "WatchlistItem",
          data: item.as_json
        }.to_json
      end

      lines.join("\n")
    end

    def family_securities_scope
      @family_securities_scope ||= begin
        security_ids = @family.trades.distinct.pluck(:security_id) + @family.holdings.distinct.pluck(:security_id)
        Security.where(id: security_ids.compact.uniq)
      end
    end
end
