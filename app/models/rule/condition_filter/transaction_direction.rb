class Rule::ConditionFilter::TransactionDirection < Rule::ConditionFilter
  def label
    "Direction"
  end

  def type
    "select"
  end

  def options
    [
      [ "Income", "income" ],
      [ "Expense", "expense" ]
    ]
  end

  def prepare(scope)
    scope.with_entry
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("CASE WHEN entries.amount < 0 THEN 'income' ELSE 'expense' END", operator, value)
    scope.where(expression)
  end
end
