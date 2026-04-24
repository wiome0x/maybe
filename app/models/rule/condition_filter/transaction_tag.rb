class Rule::ConditionFilter::TransactionTag < Rule::ConditionFilter
  def label
    "Tag"
  end

  def type
    "select"
  end

  def options
    family.tags.alphabetically.pluck(:name, :id)
  end

  def prepare(scope)
    scope.left_joins(:tags).distinct
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("tags.id", operator, value)
    scope.where(expression)
  end
end
