require "test_helper"

class InvestmentsControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:investment)
  end

  test "connect creates a draft investment account and redirects to broker connection setup" do
    assert_difference -> { Account.count }, 1 do
      post connect_investments_path
    end

    created_account = Account.order(:created_at).last

    assert_equal "Investment", created_account.accountable_type
    assert_equal "draft", created_account.status
    assert_equal "Charles Schwab", created_account.name
    assert_redirected_to new_broker_connection_path(account_id: created_account.id)
  end
end
