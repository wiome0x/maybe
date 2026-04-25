require "test_helper"

class BrokerConnectionTest < ActiveSupport::TestCase
  setup do
    @binance = broker_connections(:binance_connection)
    @account = accounts(:investment)
    @family  = families(:dylan_family)
  end

  # ---------------------------------------------------------------------------
  # Encryption: api_key, api_secret, access_token, refresh_token
  #
  # The model uses Rails Active Record Encryption (encrypts :api_key, etc.)
  # when credentials are configured.  In environments without encryption keys
  # the `encrypts` call is skipped and the virtual attributes don't exist, so
  # we only run the plaintext-check when encryption is active.
  # ---------------------------------------------------------------------------

  test "encrypted Binance fields are not stored as plaintext in the database" do
    skip "Active Record Encryption not configured in this environment" unless Rails.application.credentials.active_record_encryption.present?

    conn = BrokerConnection.create!(
      account:      accounts(:depository),
      family:       @family,
      provider:     :binance,
      status:       :active,
      connected_at: Time.current,
      api_key:      "my_plain_api_key",
      api_secret:   "my_plain_api_secret"
    )

    raw = ActiveRecord::Base.connection.execute(
      "SELECT encrypted_api_key, encrypted_api_secret FROM broker_connections WHERE id = '#{conn.id}'"
    ).first

    assert_not_equal "my_plain_api_key",    raw["encrypted_api_key"],    "api_key must not be stored as plaintext"
    assert_not_equal "my_plain_api_secret", raw["encrypted_api_secret"], "api_secret must not be stored as plaintext"
  end

  test "encrypted OAuth tokens are not stored as plaintext in the database" do
    skip "Active Record Encryption not configured in this environment" unless Rails.application.credentials.active_record_encryption.present?

    conn = BrokerConnection.create!(
      account:      accounts(:depository),
      family:       @family,
      provider:     :schwab,
      status:       :active,
      connected_at: Time.current,
      access_token:  "my_plain_access_token",
      refresh_token: "my_plain_refresh_token"
    )

    raw = ActiveRecord::Base.connection.execute(
      "SELECT encrypted_access_token, encrypted_refresh_token FROM broker_connections WHERE id = '#{conn.id}'"
    ).first

    assert_not_equal "my_plain_access_token",  raw["encrypted_access_token"],  "access_token must not be stored as plaintext"
    assert_not_equal "my_plain_refresh_token", raw["encrypted_refresh_token"], "refresh_token must not be stored as plaintext"
  end

  # ---------------------------------------------------------------------------
  # Unique constraint: one BrokerConnection per account_id
  # Validates: Requirements 1 (AC 5) — Correctness Property 4
  # ---------------------------------------------------------------------------

  test "cannot create two BrokerConnections for the same account" do
    # @binance already occupies accounts(:investment)
    assert_raises(ActiveRecord::RecordNotUnique) do
      BrokerConnection.create!(
        account:      @account,
        family:       @family,
        provider:     :binance,
        status:       :active,
        connected_at: Time.current
      )
    end
  end

  # ---------------------------------------------------------------------------
  # upsert_account_snapshot! idempotency
  # Validates: Requirements 1 (AC 2) — Correctness Property 1
  # ---------------------------------------------------------------------------

  test "upsert_account_snapshot! updates in place and does not create duplicate records" do
    payload = { "balances" => [ { "asset" => "BTC", "free" => "0.5" } ] }

    assert_no_difference "BrokerConnection.count" do
      3.times { @binance.upsert_account_snapshot!(payload) }
    end

    @binance.reload
    assert_equal payload, @binance.raw_account_payload
    assert_not_nil @binance.last_snapshot_at
  end

  test "upsert_account_snapshot! overwrites previous payload on repeated calls" do
    @binance.upsert_account_snapshot!({ "first" => true })
    @binance.upsert_account_snapshot!({ "second" => true })

    @binance.reload
    assert_equal({ "second" => true }, @binance.raw_account_payload)
  end

  # ---------------------------------------------------------------------------
  # Status enum transitions
  # ---------------------------------------------------------------------------

  test "valid statuses are accepted" do
    %w[active error requires_reauth].each do |s|
      @binance.status = s
      assert @binance.valid?, "Expected status '#{s}' to be valid"
    end
  end

  test "invalid status raises ArgumentError" do
    assert_raises(ArgumentError) do
      @binance.status = "unknown_status"
    end
  end

  test "status transitions update the record" do
    @binance.update!(status: :error)
    assert @binance.error?

    @binance.update!(status: :requires_reauth)
    assert @binance.requires_reauth?

    @binance.update!(status: :active)
    assert @binance.active?
  end
end
