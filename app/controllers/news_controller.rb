class NewsController < ApplicationController
  def index
    @articles = fetch_news
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  private
    def fetch_news
      # Eastmoney news API - returns JSON, works from any IP
      url = "https://newsapi.eastmoney.com/kuaixun/v1/getlist_102_ajaxResult_50_1_.html"
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0"
      request["Referer"] = "https://kuaixun.eastmoney.com/"

      response = http.request(request)
      return [] unless response.is_a?(Net::HTTPSuccess)

      body = response.body
      # Response is JSONP: var ajaxResult = {...}
      json_str = body[/\{.*\}/m]
      return [] if json_str.blank?

      data = JSON.parse(json_str)
      live_list = data.dig("LivesList") || []

      live_list.first(30).map do |item|
        {
          title: item["Title"],
          url: item["Url"].presence || item["DocUrl"].presence || "#",
          time: format_news_time(item["ShowTime"]),
          digest: item["Digest"]
        }
      end.select { |a| a[:title].present? }
    rescue => e
      Rails.logger.warn("Failed to fetch news: #{e.message}")
      []
    end

    def format_news_time(time_str)
      return nil if time_str.blank?
      time = Time.parse(time_str) rescue nil
      return nil unless time
      if time.to_date == Date.current
        time.strftime("%H:%M")
      else
        time.strftime("%m-%d %H:%M")
      end
    end
end
