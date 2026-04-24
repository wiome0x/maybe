require "test_helper"

class RuleTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @account = @family.accounts.create!(name: "Rule test", balance: 1000, currency: "USD", accountable: Depository.new)
    @whole_foods_merchant = @family.merchants.create!(name: "Whole Foods", type: "FamilyMerchant")
    @groceries_category = @family.categories.create!(name: "Groceries")
  end

  test "basic rule" do
    transaction_entry = create_transaction(date: Date.current, account: @account, merchant: @whole_foods_merchant)

    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [ Rule::Condition.new(condition_type: "transaction_merchant", operator: "=", value: @whole_foods_merchant.id) ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    rule.apply

    transaction_entry.reload

    assert_equal @groceries_category, transaction_entry.transaction.category
  end

  test "compound rule" do
    transaction_entry1 = create_transaction(date: Date.current, amount: 50, account: @account, merchant: @whole_foods_merchant)
    transaction_entry2 = create_transaction(date: Date.current, amount: 100, account: @account, merchant: @whole_foods_merchant)

    # Assign "Groceries" to transactions with a merchant of "Whole Foods" and an amount greater than $60
    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [
        Rule::Condition.new(condition_type: "compound", operator: "and", sub_conditions: [
          Rule::Condition.new(condition_type: "transaction_merchant", operator: "=", value: @whole_foods_merchant.id),
          Rule::Condition.new(condition_type: "transaction_amount", operator: ">", value: 60)
        ])
      ],
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ]
    )

    rule.apply

    transaction_entry1.reload
    transaction_entry2.reload

    assert_nil transaction_entry1.transaction.category
    assert_equal @groceries_category, transaction_entry2.transaction.category
  end

  test "account, category, and tag filters are available for transaction rules" do
    filter_keys = Rule.new(family: @family, resource_type: "transaction").condition_filters.map(&:key)

    assert_includes filter_keys, "transaction_account"
    assert_includes filter_keys, "transaction_direction"
    assert_includes filter_keys, "transaction_kind"
    assert_includes filter_keys, "transaction_category"
    assert_includes filter_keys, "transaction_tag"
  end

  test "rule summaries are human readable" do
    transaction_entry = create_transaction(date: Date.current, amount: 100, account: @account, merchant: @whole_foods_merchant, name: "Whole Foods Market")
    travel_tag = @family.tags.create!(name: "Travel")

    rule = Rule.create!(
      family: @family,
      resource_type: "transaction",
      effective_date: 1.day.ago.to_date,
      conditions: [
        Rule::Condition.new(condition_type: "transaction_name", operator: "like", value: "Whole Foods"),
        Rule::Condition.new(condition_type: "transaction_account", operator: "=", value: @account.id)
      ],
      actions: [
        Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id),
        Rule::Action.new(action_type: "set_transaction_tags", value: [ travel_tag.id ])
      ]
    )

    assert_equal "Description contains Whole Foods AND Account equal to Rule test", rule.conditions_summary
    assert_equal "Set category to Groceries AND Add tags Travel", rule.actions_summary
  end

  # Artificial limitation put in place to prevent users from creating overly complex rules
  # Rules should be shallow and wide
  test "no nested compound conditions" do
    rule = Rule.new(
      family: @family,
      resource_type: "transaction",
      actions: [ Rule::Action.new(action_type: "set_transaction_category", value: @groceries_category.id) ],
      conditions: [
        Rule::Condition.new(condition_type: "compound", operator: "and", sub_conditions: [
          Rule::Condition.new(condition_type: "compound", operator: "and", sub_conditions: [
            Rule::Condition.new(condition_type: "transaction_name", operator: "=", value: "Starbucks")
          ])
        ])
      ]
    )

    assert_not rule.valid?
    assert_equal [ "Compound conditions cannot be nested" ], rule.errors.full_messages
  end
end
