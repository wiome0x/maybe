require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    clear_enqueued_jobs
  end

  test "can supply custom redirect after update" do
    patch user_url(@user), params: { user: { redirect_to: "home" } }
    assert_redirected_to root_url
  end

  test "can update user profile" do
    patch user_url(@user), params: {
      user: {
        first_name: "John",
        last_name: "Doe",
        onboarded_at: Time.current,
        profile_image: file_fixture_upload("profile_image.png", "image/png", :binary),
        family_attributes: {
          name: "New Family Name",
          country: "US",
          date_format: "%m/%d/%Y",
          currency: "USD",
          locale: "en"
        }
      }
    }

    assert_redirected_to settings_profile_url
    assert_equal "Your profile has been updated.", flash[:notice]
  end

  test "admin can reset family data" do
    account = accounts(:investment)
    category = categories(:income)
    tag = tags(:one)
    merchant = merchants(:netflix)
    import = imports(:transaction)
    budget = budgets(:one)
    plaid_item = plaid_items(:one)

    Provider::Plaid.any_instance.expects(:remove_item).with(plaid_item.access_token).once

    perform_enqueued_jobs(only: FamilyResetJob) do
      delete reset_user_url(@user)
    end

    assert_redirected_to settings_profile_url
    assert_equal I18n.t("users.reset.success"), flash[:notice]

    assert_not Account.exists?(account.id)
    assert_not Category.exists?(category.id)
    assert_not Tag.exists?(tag.id)
    assert_not Merchant.exists?(merchant.id)
    assert_not Import.exists?(import.id)
    assert_not Budget.exists?(budget.id)
    assert_not PlaidItem.exists?(plaid_item.id)
  end

  test "non-admin cannot reset family data" do
    sign_in @member = users(:family_member)

    delete reset_user_url(@member)

    assert_redirected_to settings_profile_url
    assert_equal I18n.t("users.reset.unauthorized"), flash[:alert]
    assert_no_enqueued_jobs only: FamilyResetJob
  end

  test "member can deactivate their account" do
    sign_in @member = users(:family_member)
    delete user_url(@member)

    assert_redirected_to root_url

    assert_not User.find(@member.id).active?
    assert_enqueued_with(job: UserPurgeJob, args: [ @member ])
  end

  test "deactivate revokes sessions api keys and oauth tokens" do
    sign_in @member = users(:family_member)

    @member.api_keys.create!(
      name: "Mobile API Key",
      key: "member_active_key_123",
      scopes: [ "read_write" ],
      source: "web"
    )

    device = @member.mobile_devices.create!(
      device_id: "device-123",
      device_name: "iPhone",
      device_type: "ios",
      os_version: "18.0",
      app_version: "1.0.0"
    )
    oauth_app = device.create_oauth_application!
    access_token = Doorkeeper::AccessToken.create!(
      application: oauth_app,
      resource_owner_id: @member.id,
      expires_in: 30.days.to_i,
      scopes: "read_write",
      use_refresh_token: true
    )

    assert @member.sessions.any?
    assert @member.api_keys.active.any?
    assert_nil access_token.reload.revoked_at

    delete user_url(@member)

    assert_redirected_to root_url
    assert_equal 0, @member.sessions.reload.count
    assert_equal 0, @member.api_keys.active.count
    assert access_token.reload.revoked_at.present?
  end

  test "admin prevented from deactivating when other users are present" do
    sign_in @admin = users(:family_admin)
    delete user_url(users(:family_member))

    assert_redirected_to settings_profile_url
    assert_equal "Admin cannot delete account while other users are present. Please delete all members first.", flash[:alert]
    assert_no_enqueued_jobs only: UserPurgeJob
    assert User.find(@admin.id).active?
  end

  test "admin can deactivate their account when they are the last user in the family" do
    sign_in @admin = users(:family_admin)
    users(:family_member).destroy

    delete user_url(@admin)

    assert_redirected_to root_url
    assert_not User.find(@admin.id).active?
    assert_enqueued_with(job: UserPurgeJob, args: [ @admin ])
  end
end
