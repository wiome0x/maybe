class Rule::Action < ApplicationRecord
  belongs_to :rule, touch: true

  validates :action_type, presence: true

  def value=(raw_value)
    normalized_value =
      if raw_value.is_a?(Array)
        raw_value.reject(&:blank?).to_json
      else
        raw_value
      end

    super(normalized_value)
  end

  def apply(resource_scope, ignore_attribute_locks: false)
    executor.execute(resource_scope, value: value, ignore_attribute_locks: ignore_attribute_locks)
  end

  def options
    executor.options
  end

  def value_display
    return "" if value.blank?
    return "" unless options

    if executor.type == "select_multiple"
      selected_labels = options.select { |option| selected_values.include?(option.last) }.map(&:first)
      selected_labels.join(", ")
    else
      options.find { |option| option.last == value }&.first.to_s
    end
  end

  def executor
    rule.registry.get_executor!(action_type)
  end

  def selected_values
    parsed_values
  end

  def summary
    return executor.label if value.blank? || options.blank?

    if executor.type == "select_multiple"
      [ executor.label, value_display ].reject(&:blank?).join(" ")
    else
      [ executor.label, "to", value_display ].reject(&:blank?).join(" ")
    end
  end

  private
    def parsed_values
      case value
      when Array
        value
      when String
        value.strip.start_with?("[") ? JSON.parse(value) : value.split(",")
      else
        Array(value)
      end
    rescue JSON::ParserError
      []
    end
end
