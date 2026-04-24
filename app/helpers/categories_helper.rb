module CategoriesHelper
  FOREX_PAIR_NAME_PATTERN = /\A[A-Z]{3}\.[A-Z]{3}\z/

  def transfer_category
    Category.new \
      name: "Transfer",
      color: Category::TRANSFER_COLOR,
      lucide_icon: "arrow-right-left"
  end

  def payment_category
    Category.new \
      name: "Payment",
      color: Category::PAYMENT_COLOR,
      lucide_icon: "arrow-right"
  end

  def trade_category
    Category.new \
      name: "Trade",
      color: Category::TRADE_COLOR
  end

  def trade_direction_category(trade)
    if trade.qty.positive?
      Category.new(
        name: "Buy",
        color: "#2563EB",
        lucide_icon: "arrow-down"
      )
    else
      Category.new(
        name: "Sell",
        color: "#0F766E",
        lucide_icon: "arrow-up"
      )
    end
  end

  def movement_direction_category(entry)
    name = if forex_pair_entry?(entry)
      entry.amount.negative? ? "Fx Inflow" : "Fx Outflow"
    else
      entry.amount.negative? ? "Cash Inflow" : "Cash Outflow"
    end
    inflow = entry.amount.negative?

    Category.new(
      name: name,
      color: inflow ? "#15803D" : "#B45309",
      lucide_icon: inflow ? "arrow-down-left" : "arrow-up-right"
    )
  end

  def family_categories
    [ Category.uncategorized ].concat(Current.family.categories.alphabetically)
  end

  private
    def forex_pair_entry?(entry)
      FOREX_PAIR_NAME_PATTERN.match?(entry.name.to_s)
    end
end
