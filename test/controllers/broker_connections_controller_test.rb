require "test_helper"

class BrokerConnectionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = families(:dylan_family)
    @investment_account = accounts(:investment)
    @crypto_account = accounts(:crypto)
    @binance_connection = broker_connections(:binance_connection)
    @schwab_connection = broker_connections(:schwab_connection)
  end

  # ---------------------------------------------------------------------------
  # create (Binance) — valid credentials
  # Validates: Requirement 7 (AC 4)
  # ---------------------------------------------------------------------------

  test "create with valid Binance credentials creates BrokerConnection and redirects" do
    # investment account already has a binance_connection fixture; use a fresh account
    fresh_account = Account.create!(
      family: @family,
      name: "New Crypto Account",
      balance: 0,
      currency: "USD",
      accountable: Crypto.create!,
      status: "draft"
    )

    success_response = Provider::Response.new(success?: true, data: {}, error: nil)
    Provider::Binance.any_instance.expects(:validate_credentials!).once.returns(success_response)
    BrokerConnection.any_instance.expects(:sync_later).once

    assert_difference "BrokerConnection.count", 1 do
      post broker_connections_url, params: {
        broker_connection: {
          account_id: fresh_account.id,
          api_key: "valid_key",
          api_secret: "valid_secret"
        }
      }
    end

    assert_redirected_to account_path(fresh_account)
    assert_equal "Binance account connected successfully.", flash[:notice]
    assert_equal "active", fresh_account.reload.status
  end

  test "create with return_to redirects back to the provided local path" do
    fresh_account = Account.create!(
      family: @family,
      name: "Return Path Crypto Account",
      balance: 0,
      currency: "USD",
      accountable: Crypto.create!,
      status: "draft"
    )

    success_response = Provider::Response.new(success?: true, data: {}, error: nil)
    Provider::Binance.any_instance.expects(:validate_credentials!).once.returns(success_response)
    BrokerConnection.any_instance.expects(:sync_later).once

    post broker_connections_url, params: {
      return_to: accounts_path,
      broker_connection: {
        account_id: fresh_account.id,
        api_key: "valid_key",
        api_secret: "valid_secret"
      }
    }

    assert_redirected_to accounts_path
    assert_equal "active", fresh_account.reload.status
  end

  # ---------------------------------------------------------------------------
  # create (Binance) — invalid credentials
  # Validates: Requirement 7 (AC 6)
  # ---------------------------------------------------------------------------

  test "create with invalid Binance credentials renders new with error and does not create record" do
    fresh_account = Account.create!(
      family: @family,
      name: "Another Crypto Account",
      balance: 0,
      currency: "USD",
      accountable: Crypto.create!
    )

    Provider::Binance.any_instance.expects(:validate_credentials!).raises(
      Provider::Error.new("Binance auth error: invalid API key or signature")
    )

    assert_no_difference "BrokerConnection.count" do
      post broker_connections_url, params: {
        broker_connection: {
          account_id: fresh_account.id,
          api_key: "bad_key",
          api_secret: "bad_secret"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # schwab_callback — valid OAuth code
  # Validates: Requirement 7 (AC 5)
  # ---------------------------------------------------------------------------

  test "schwab_callback with valid code creates BrokerConnection and redirects" do
    fresh_account = Account.create!(
      family: @family,
      name: "New Investment Account",
      balance: 0,
      currency: "USD",
      accountable: Investment.create!,
      status: "draft"
    )

    Provider::Schwab.expects(:exchange_code).with(code: "auth_code_123").returns({
      access_token: "access_abc",
      refresh_token: "refresh_xyz",
      expires_in: 3600,
      broker_account_id: "schwab-acct-001"
    })
    BrokerConnection.any_instance.expects(:sync_later).once

    assert_difference "BrokerConnection.count", 1 do
      get auth_schwab_callback_url, params: { code: "auth_code_123", state: fresh_account.id }
    end

    assert_redirected_to account_path(fresh_account)
    assert_equal "Charles Schwab account connected successfully.", flash[:notice]
    assert_equal "active", fresh_account.reload.status
  end

  test "schwab_callback honors return_to from signed onboarding state" do
    fresh_account = Account.create!(
      family: @family,
      name: "Return Path Investment Account",
      balance: 0,
      currency: "USD",
      accountable: Investment.create!,
      status: "draft"
    )

    # Stub the onboarding service to return a known state without needing secret_key_base
    BrokerOnboarding.any_instance.stubs(:resolve_state).returns({
      account_id: fresh_account.id,
      return_to: accounts_path
    })

    Provider::Schwab.expects(:exchange_code).with(code: "auth_code_123").returns({
      access_token: "access_abc",
      refresh_token: "refresh_xyz",
      expires_in: 3600,
      broker_account_id: "schwab-acct-001"
    })
    BrokerConnection.any_instance.expects(:sync_later).once

    get auth_schwab_callback_url, params: { code: "auth_code_123", state: "any_state" }

    assert_redirected_to accounts_path
    assert_equal "active", fresh_account.reload.status
  end

  # ---------------------------------------------------------------------------
  # destroy — removes connection, responds with Turbo Stream
  # Validates: Requirement 8 (AC 4)
  # ---------------------------------------------------------------------------

  test "destroy removes BrokerConnection and redirects for HTML" do
    assert_difference "BrokerConnection.count", -1 do
      delete broker_connection_url(@binance_connection)
    end

    assert_redirected_to account_path(@investment_account)
    assert_equal "Broker connection removed.", flash[:notice]
  end

  test "destroy responds with turbo_stream redirect" do
    assert_difference "BrokerConnection.count", -1 do
      delete broker_connection_url(@binance_connection), headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # Authorization — non-family member cannot operate on another family's connection
  # Validates: Requirement 7 & 8 (family scoping)
  # ---------------------------------------------------------------------------

  test "cannot destroy a BrokerConnection belonging to another family" do
    other_family = families(:empty)
    other_user = users(:empty)

    other_account = Account.create!(
      family: other_family,
      name: "Other Family Account",
      balance: 0,
      currency: "USD",
      accountable: Crypto.create!
    )

    other_connection = BrokerConnection.create!(
      account: other_account,
      family: other_family,
      provider: :binance,
      status: :active,
      connected_at: Time.current
    )

    sign_in @user  # signed in as dylan_family admin

    assert_no_difference "BrokerConnection.count" do
      delete broker_connection_url(other_connection)
    end

    assert_response :not_found
  end
end
