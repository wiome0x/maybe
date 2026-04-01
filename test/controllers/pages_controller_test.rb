require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
  end

  test "dashboard" do
    get root_path
    assert_response :ok
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
