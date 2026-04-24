class Rule::ConditionFilter::TransactionKind < Rule::ConditionFilter
  def label
    "Transaction type"
  end

  def type
    "select"
  end

  def options
    [
      [ "Standard", "standard" ],
      [ "Transfer", "funds_movement" ],
      [ "Credit card payment", "cc_payment" ],
      [ "Loan payment", "loan_payment" ],
      [ "One-time", "one_time" ]
    ]
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("transactions.kind", operator, value)
    scope.where(expression)
  end
end
