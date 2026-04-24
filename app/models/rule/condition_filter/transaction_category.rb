class Rule::ConditionFilter::TransactionCategory < Rule::ConditionFilter
  def label
    "Category"
  end

  def type
    "select"
  end

  def options
    family.categories.alphabetically.map { |category| [ category.display_name, category.id ] }
  end

  def prepare(scope)
    scope.left_joins(:category)
  end

  def apply(scope, operator, value)
    expression = build_sanitized_where_condition("categories.id", operator, value)
    scope.where(expression)
  end
end
