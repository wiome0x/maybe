require "test_helper"

class Family::SyncerTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "syncs plaid items and manual accounts" do
    family_sync = syncs(:family)

    items_count = @family.plaid_items.count
    broker_backed_accounts = @family.accounts.manual.visible.select(&:broker_connection)
    direct_manual_accounts = @family.accounts.manual.visible.reject(&:broker_connection)

    syncer = Family::Syncer.new(@family)

    Account.any_instance
           .expects(:sync_later)
           .with(parent_sync: family_sync, window_start_date: nil, window_end_date: nil)
           .times(direct_manual_accounts.count)

    BrokerConnection.any_instance
                    .expects(:sync_later)
                    .with(parent_sync: family_sync, window_start_date: nil, window_end_date: nil)
                    .times(broker_backed_accounts.count)

    PlaidItem.any_instance
             .expects(:sync_later)
             .with(parent_sync: family_sync, window_start_date: nil, window_end_date: nil)
             .times(items_count)

    syncer.perform_sync(family_sync)

    assert_equal "completed", family_sync.reload.status
  end

  test "perform_post_sync only applies active rules" do
    syncer = Family::Syncer.new(@family)
    category = categories(:food_and_drink)
    action = -> { Rule::Action.new(action_type: "set_transaction_category", value: category.id) }
    @family.rules.create!(resource_type: "transaction", active: true, actions: [ action.call ])
    @family.rules.create!(resource_type: "transaction", active: false, actions: [ action.call ])

    assert_equal 1, @family.rules.active.count

    Rule.any_instance.expects(:apply_later).once
    @family.expects(:auto_match_transfers!).once

    syncer.perform_post_sync
  end
end
