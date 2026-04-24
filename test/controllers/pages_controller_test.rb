require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
  end

  test "dashboard shows converted account balances in family currency" do
    family = @user.family
    family.update!(currency: "USD")

    account = family.accounts.create!(
      name: "EUR Checking",
      balance: 100,
      cash_balance: 100,
      currency: "EUR",
      accountable: Depository.create!
    )

    ExchangeRate.create!(
      from_currency: "EUR",
      to_currency: "USD",
      rate: 1.1,
      date: Date.current
    )

    get root_path

    assert_response :ok
    assert_select "#balance-sheet", text: /\$110\.00/
    assert_select "#balance-sheet", text: /EUR Checking/
    assert_select "#balance-sheet", text: /€100\.00/
  ensure
    account&.destroy
  end

  test "changelog" do
    get changelog_path
    assert_response :ok
  end

  test "changelog renders without commits" do
    PagesController.any_instance.stubs(:fetch_git_commits).returns([])

    get changelog_path
    assert_response :ok
    assert_select "p", text: "No commit history available."
  end
end
