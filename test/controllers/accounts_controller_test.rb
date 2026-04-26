require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @account = accounts(:depository)
  end

  test "should get index" do
    get accounts_url
    assert_response :success
  end

  test "index groups unfinished broker setup accounts separately" do
    Account.create!(
      family: @user.family,
      name: "Pending Binance Setup",
      balance: 0,
      cash_balance: 0,
      currency: "USD",
      accountable: Crypto.create!,
      status: "draft"
    )

    get accounts_url

    assert_response :success
    assert_includes response.body, "Setup in progress"
    assert_includes response.body, "Pending Binance Setup"
    assert_includes response.body, "Continue setup"
  end

  test "should get show" do
    get account_url(@account)
    assert_response :success
  end

  test "should sync account" do
    Account.any_instance.expects(:sync_later).once
    post sync_account_url(@account)
    assert_redirected_to account_url(@account)
  end

  test "should sync broker connection for broker-backed account" do
    broker_account = accounts(:investment)
    BrokerConnection.any_instance.expects(:sync_later).once

    post sync_account_url(broker_account)

    assert_redirected_to account_url(broker_account)
  end

  test "should get sparkline" do
    get sparkline_account_url(@account)
    assert_response :success
  end

  test "destroys account" do
    delete account_url(@account)
    assert_redirected_to accounts_path
    assert_enqueued_with job: DestroyJob
    assert_equal "Account scheduled for deletion", flash[:notice]
  end
end
