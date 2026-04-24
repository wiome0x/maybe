class Rule::ConditionFilter::TransactionAccount < Rule::ConditionFilter
  def label
    "Account"
  end

  def type
    "select"
  end

  def options
    family.accounts.visible.alphabetically.pluck(:name, :id)
  end

  def prepare(scope)
    scope.with_entry
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("entries.account_id", operator, value)
    scope.where(expression)
  end
end
