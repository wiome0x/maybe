class Rule::ActionExecutor::SetTransactionTags < Rule::ActionExecutor
  def label
    "Add tags"
  end

  def type
    "select_multiple"
  end

  def options
    family.tags.pluck(:name, :id)
  end

  def execute(transaction_scope, value: nil, ignore_attribute_locks: false)
    tag_ids = normalized_tag_ids(value)
    return if tag_ids.empty?

    scope = transaction_scope

    unless ignore_attribute_locks
      scope = scope.enrichable(:tag_ids)
    end

    scope.each do |txn|
      txn.enrich_attribute(
        :tag_ids,
        (txn.tag_ids + tag_ids).uniq,
        source: "rule"
      )
    end
  end

  private
    def normalized_tag_ids(value)
      raw_values =
        case value
        when Array
          value
        when String
          value.strip.start_with?("[") ? JSON.parse(value) : value.split(",")
        else
          Array(value)
        end

      family.tags.where(id: raw_values.map(&:presence).compact).pluck(:id)
    rescue JSON::ParserError
      []
    end
end
