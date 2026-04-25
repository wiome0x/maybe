require "test_helper"

class AppUrlBuilderTest < ActiveSupport::TestCase
  test "builds full url from configured default url options" do
    url = AppUrlBuilder.url_for("/settings/weekly_reports")

    assert_equal "https://example.com/settings/weekly_reports", url
  end

  test "preserves non standard ports" do
    Rails.application.config.action_mailer.default_url_options = { host: "localhost", protocol: "http", port: 3000 }

    url = AppUrlBuilder.url_for("/markets/stocks/news")

    assert_equal "http://localhost:3000/markets/stocks/news", url
  ensure
    Rails.application.config.action_mailer.default_url_options = { host: "example.com" }
  end
end
