require "test_helper"
require "webmock/minitest"

class BarkNotifierTest < ActiveSupport::TestCase
  test "posts payload to bark server" do
    subscription = users(:family_admin).build_bark_notification_subscription(
      server_url: "https://api.day.app",
      device_key: "abc123"
    )

    stub_request(:post, "https://api.day.app/abc123")
      .with do |request|
        payload = JSON.parse(request.body)

        request.headers["Content-Type"] == "application/json; charset=utf-8" &&
          payload["title"] == "Market move" &&
          payload["body"] == "S&P 500 rose sharply" &&
          payload["url"] == "https://example.com/news"
      end
      .to_return(status: 200, body: { code: 200, message: "success" }.to_json, headers: { "Content-Type" => "application/json" })

    response = BarkNotifier.new(subscription).deliver(
      title: "Market move",
      body: "S&P 500 rose sharply",
      url: "https://example.com/news"
    )

    assert_equal 200, response["code"]
    assert_requested :post, "https://api.day.app/abc123", times: 1
  end
end
