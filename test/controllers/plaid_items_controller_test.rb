require "test_helper"
require "ostruct"

class PlaidItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @user.setup_mfa!
    @user.enable_mfa!
  end

  test "create" do
    @plaid_provider = mock
    Provider::Registry.expects(:plaid_provider_for_region).with("us").returns(@plaid_provider)

    public_token = "public-sandbox-1234"

    @plaid_provider.expects(:exchange_public_token).with(public_token).returns(
      OpenStruct.new(access_token: "access-sandbox-1234", item_id: "item-sandbox-1234")
    )

    assert_difference "PlaidItem.count", 1 do
      post plaid_items_url, params: {
        plaid_item: {
          public_token: public_token,
          region: "us",
          metadata: { institution: { name: "Plaid Item Name" } }
        }
      }
    end

    assert_equal "Account linked successfully.  Please wait for accounts to sync.", flash[:notice]
    assert_redirected_to accounts_path
  end

  test "destroy" do
    delete plaid_item_url(plaid_items(:one))

    assert_equal "Accounts scheduled for deletion.", flash[:notice]
    assert_enqueued_with job: DestroyJob
    assert_redirected_to accounts_path
  end

  test "sync" do
    plaid_item = plaid_items(:one)
    PlaidItem.any_instance.expects(:sync_later).once

    post sync_plaid_item_url(plaid_item)

    assert_redirected_to accounts_path
  end

  test "authoritative_rebuild" do
    plaid_item = plaid_items(:one)

    PlaidItem.any_instance.expects(:authoritative_rebuild_and_sync_later).once.returns(
      imported_entries: 27,
      holdings: 132,
      balances: 47,
      sync_id: "sync-123",
      sync_status: "pending"
    )

    post authoritative_rebuild_plaid_item_url(plaid_item)

    assert_redirected_to accounts_path
    assert_equal "Rebuild started. Cleared 27 imported entries, 132 holdings, and 47 balances.", flash[:notice]
  end

  test "authoritative_rebuild handles errors" do
    plaid_item = plaid_items(:one)
    PlaidItem.any_instance.expects(:authoritative_rebuild_and_sync_later).raises(StandardError.new("boom"))

    post authoritative_rebuild_plaid_item_url(plaid_item)

    assert_redirected_to accounts_path
    assert_equal "Could not rebuild this connection. Please try again.", flash[:alert]
  end

  test "new requires mfa before opening plaid link" do
    user = users(:family_member)
    sign_in user

    get new_plaid_item_url(region: "us", accountable_type: "Investment")

    assert_redirected_to settings_security_path
    assert_equal "Enable multi-factor authentication in Security settings before connecting or syncing Plaid accounts.", flash[:alert]
  end

  test "create requires mfa before linking plaid item" do
    user = users(:family_member)
    sign_in user

    assert_no_difference "PlaidItem.count" do
      post plaid_items_url, params: {
        plaid_item: {
          public_token: "public-sandbox-1234",
          region: "us",
          metadata: { institution: { name: "Blocked Institution" } }
        }
      }
    end

    assert_redirected_to settings_security_path
    assert_equal "Enable multi-factor authentication in Security settings before connecting or syncing Plaid accounts.", flash[:alert]
  end
end
