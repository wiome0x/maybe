class NewsController < ApplicationController
  def index
    @articles = fetch_news
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  private
    def fetch_news
      url = "https://stock.eastmoney.com/a/cmgdd.html"
      uri = URI(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
      request["Accept"] = "text/html"

      response = http.request(request)
      return [] unless response.is_a?(Net::HTTPSuccess)

      body = response.body.force_encoding("GBK").encode("UTF-8", invalid: :replace, undef: :replace)
      parse_news_html(body)
    rescue => e
      Rails.logger.warn("Failed to fetch news: #{e.message}")
      []
    end

    def parse_news_html(html)
      # Eastmoney news list items follow pattern:
      # <div class="newsList">
      #   <li>
      #     <a href="..." title="...">title</a>
      #     <span class="time">date</span>
      #   </li>
      # </div>
      articles = []

      # Extract list items with regex (avoid adding nokogiri dependency)
      html.scan(/<li[^>]*>.*?<\/li>/m).each do |li|
        # Extract link and title
        href = li[/href="([^"]*)"/, 1]
        title = li[/title="([^"]*)"/, 1] || li[/<a[^>]*>([^<]+)<\/a>/, 1]
        time = li[/<span[^>]*class="time"[^>]*>([^<]+)<\/span>/, 1]

        next if title.blank? || href.blank?

        # Make URL absolute
        href = "https://stock.eastmoney.com#{href}" if href.start_with?("/")

        articles << { title: title.strip, url: href, time: time&.strip }
      end

      articles.first(30)
    end
end
