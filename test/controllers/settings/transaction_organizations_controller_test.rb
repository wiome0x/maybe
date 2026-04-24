require "test_helper"

class Settings::TransactionOrganizationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
  end

  test "should get show" do
    get settings_transaction_organization_path
    assert_response :success
    assert_includes response.body, categories_path
    assert_includes response.body, family_merchants_path
    assert_includes response.body, tags_path
    assert_includes response.body, rules_path
  end
end
