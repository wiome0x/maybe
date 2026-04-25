require "net/http"
require "json"

class BarkNotifier
  DEFAULT_SERVER_URL = "https://api.day.app".freeze

  def initialize(subscription)
    @subscription = subscription
  end

  def deliver(title:, body:, url: nil, group: nil, sound: nil, icon: nil)
    raise ArgumentError, "Bark subscription is not configured" unless subscription&.configured?

    uri = URI("#{subscription.server_url}/#{ERB::Util.url_encode(subscription.device_key)}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json; charset=utf-8"
    request.body = {
      title: title.to_s.truncate(120),
      body: body.to_s.truncate(3800),
      url: url,
      group: group || subscription.group_name,
      sound: sound || subscription.sound,
      icon: icon || subscription.icon
    }.compact.to_json

    response = http.request(request)
    raise "Bark push failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

    response.body.present? ? JSON.parse(response.body) : {}
  end

  private
    attr_reader :subscription
end
