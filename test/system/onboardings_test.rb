require "application_system_test_case"

class OnboardingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family

    # Reset onboarding state
    @user.update!(set_onboarding_preferences_at: nil)

    sign_in @user
  end

  test "can complete the full onboarding flow" do
    visit onboarding_path

    assert_text "Let's set up your account"
    assert_button "Continue"

    click_button "Continue"

    assert_current_path preferences_onboarding_path
    assert_text "Configure your preferences"

    assert_selector "[data-controller='time-series-chart']"

    select "English (en)", from: "user_family_attributes_locale"

    # Currency format: "USD $ - United States Dollar"
    usd_option = Money::Currency.new("USD").display_option_label
    select usd_option, from: "user_family_attributes_currency"
    select "MM/DD/YYYY", from: "user_family_attributes_date_format"
    select "Light", from: "user_theme"

    click_button "Complete"

    assert_current_path goals_onboarding_path
    assert_text "What brings you to Maybe?"
  end

  test "preferences page renders chart without errors" do
    visit preferences_onboarding_path

    assert_selector "[data-controller='time-series-chart']"
    assert_selector "#previewChart"

    chart_element = find("[data-controller='time-series-chart']")
    chart_data = chart_element["data-time-series-chart-data-value"]

    assert_nothing_raised do
      JSON.parse(chart_data)
    end

    assert_text "Example"
  end

  test "can change currency and see preview update" do
    visit preferences_onboarding_path

    eur_option = Money::Currency.new("EUR").display_option_label
    select eur_option, from: "user_family_attributes_currency"

    assert_text "Example"
  end

  test "can change date format and see preview update" do
    visit preferences_onboarding_path

    select "DD/MM/YYYY", from: "user_family_attributes_date_format"

    assert_text "Example"
  end

  test "can change theme" do
    visit preferences_onboarding_path

    select "Dark", from: "user_theme"

    assert_text "Example"
  end

  test "preferences form saves data correctly" do
    visit preferences_onboarding_path

    select "Spanish (es)", from: "user_family_attributes_locale"
    eur_option = Money::Currency.new("EUR").display_option_label
    select eur_option, from: "user_family_attributes_currency"
    select "DD/MM/YYYY", from: "user_family_attributes_date_format"
    select "Dark", from: "user_theme"

    click_button "Complete"

    assert_current_path goals_onboarding_path

    @family.reload
    @user.reload

    assert_equal "es", @family.locale
    assert_equal "EUR", @family.currency
    assert_equal "%d/%m/%Y", @family.date_format
    assert_equal "dark", @user.theme
    assert_not_nil @user.set_onboarding_preferences_at
  end

  test "goals page renders correctly" do
    @user.update!(set_onboarding_preferences_at: Time.current)

    visit goals_onboarding_path

    assert_text "What brings you to Maybe?"
    assert_button "Next"
  end

  test "navigation between onboarding steps" do
    visit onboarding_path
    click_button "Continue"

    assert_current_path preferences_onboarding_path

    select "English (en)", from: "user_family_attributes_locale"
    usd_option = Money::Currency.new("USD").display_option_label
    select usd_option, from: "user_family_attributes_currency"
    select "MM/DD/YYYY", from: "user_family_attributes_date_format"
    click_button "Complete"

    assert_current_path goals_onboarding_path
  end

  test "logout option is available during onboarding" do
    visit preferences_onboarding_path

    assert_text "Sign out"
  end

  private

    def sign_in(user)
      visit new_session_path
      within "form" do
        fill_in "Email", with: user.email
        fill_in "Password", with: user_password_test
        click_on "Log in"
      end

      assert_current_path root_path
    end
end
