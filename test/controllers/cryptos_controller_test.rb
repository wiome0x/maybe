require "test_helper"

class CryptosControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:crypto)
  end

  test "connect creates a draft crypto account and redirects to broker connection setup" do
    assert_difference -> { Account.count }, 1 do
      post connect_cryptos_path
    end

    created_account = Account.order(:created_at).last

    assert_equal "Crypto", created_account.accountable_type
    assert_equal "draft", created_account.status
    assert_equal "Binance", created_account.name
    assert_redirected_to new_broker_connection_path(account_id: created_account.id)
  end
end
