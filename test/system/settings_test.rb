require "application_system_test_case"

class SettingsTest < ApplicationSystemTestCase
  setup do
    sign_in @user = users(:family_admin)
  end

  test "can access settings from sidebar" do
    open_settings_from_sidebar
    assert_selector "h1", text: "Account"
    assert_current_path settings_profile_path, ignore_query: true

    # Navigate through settings links that exist in the current nav
    click_link "Preferences"
    assert_current_path settings_preferences_path

    click_link "Accounts"
    assert_current_path accounts_path

    click_link "Tags"
    assert_current_path tags_path

    click_link "Categories"
    assert_current_path categories_path

    click_link "Merchants"
    assert_current_path family_merchants_path

    click_link "Imports"
    assert_current_path imports_path
  end

  test "can update self hosting settings" do
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    Provider::Registry.stubs(:get_provider).with(:synth).returns(nil)
    open_settings_from_sidebar
    assert_selector "li", text: "Self hosting"
    click_link "Self hosting"
    assert_current_path settings_hosting_path
    assert_selector "h1", text: "Self-Hosting"
    check "setting[require_invite_for_signup]", allow_label_click: true
    click_button "Generate new code"
    assert_selector 'span[data-clipboard-target="source"]', visible: true, count: 1
    copy_button = find('button[data-action="clipboard#copy"]', match: :first)
    copy_button.click
    assert_selector 'span[data-clipboard-target="iconSuccess"]', visible: true, count: 1
  end

  test "does not show billing link if self hosting" do
    Rails.application.config.app_mode.stubs(:self_hosted?).returns(true)
    open_settings_from_sidebar
    assert_no_selector "li", text: I18n.t("settings.settings_nav.billing_label")
  end

  private

    def open_settings_from_sidebar
      within "div[data-testid=user-menu]" do
        find("button").click
      end
      click_link "Settings"
    end
end
