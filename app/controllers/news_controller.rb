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
      request["Accept-Encoding"] = "identity"

      response = http.request(request)
      return [] unless response.is_a?(Net::HTTPSuccess)

      # Try UTF-8 first, fall back to GBK
      body = response.body
      body = if body.valid_encoding?
               body.encode("UTF-8", invalid: :replace, undef: :replace)
             else
               body.force_encoding("GBK").encode("UTF-8", invalid: :replace, undef: :replace)
             end

      parse_news_html(body)
    rescue => e
      Rails.logger.warn("Failed to fetch news: #{e.message}")
      []
    end

    def parse_news_html(html)
      articles = []

      # Extract news list section
      news_section = html[/<div[^>]*class="[^"]*newsList[^"]*"[^>]*>(.*?)<\/div>/m, 1]
      news_section ||= html

      # Extract list items
      news_section.scan(/<li[^>]*>(.*?)<\/li>/m).each do |match|
        li = match[0]

        href = li[/href="([^"]*)"/, 1]
        title = li[/title="([^"]*)"/, 1]
        title ||= li[/<a[^>]*>([^<]+)<\/a>/, 1]
        time = li[/<span[^>]*class="time"[^>]*>([^<]+)<\/span>/, 1]

        next if title.blank? || href.blank?

        # Clean title - strip any HTML tags
        clean_title = title.gsub(/<[^>]+>/, "").strip
        next if clean_title.blank?

        # Make URL absolute
        href = "https://stock.eastmoney.com#{href}" if href.start_with?("/")
        href = "https:#{href}" if href.start_with?("//")

        articles << { title: clean_title, url: href, time: time&.strip }
      end

      articles.first(30)
    end
end
