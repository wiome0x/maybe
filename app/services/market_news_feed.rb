require "cgi"
require "net/http"
require "nokogiri"

class MarketNewsFeed
  Item = Data.define(:source, :title, :url, :published_at, :translated_title)

  FEEDS = [
    {
      source: "CNBC",
      url: "https://www.cnbc.com/id/20409666/device/rss/rss.html"
    },
    {
      source: "Seeking Alpha",
      url: "https://seekingalpha.com/market_currents.xml"
    },
    {
      source: "SEC",
      url: "https://www.sec.gov/news/pressreleases.rss"
    },
    {
      source: "MarketWatch",
      url: "https://feeds.content.dowjones.io/public/rss/mw_topstories"
    }
  ].freeze

  CACHE_KEY = "markets/news_feed:v2".freeze
  CACHE_TTL = 10.minutes
  ITEM_LIMIT = 12

  def self.fetch(force_refresh: false)
    return fetch_all_feeds if force_refresh

    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { fetch_all_feeds }
  end

  def self.fetch_feed(feed)
    response = http_get(feed[:url])
    return [] unless response.is_a?(Net::HTTPSuccess)

    xml = Nokogiri::XML(response.body)
    return [] if xml.errors.present?

    xml.css("channel > item").filter_map do |item|
      title = normalize_text(item.at_css("title")&.text)
      link = item.at_css("link")&.text.to_s.strip
      next if title.blank? || link.blank?

      published_at = begin
        pub_date = item.at_css("pubDate")&.text
        pub_date.present? ? Time.zone.parse(pub_date) : nil
      rescue
        nil
      end

      Item.new(
        source: feed[:source],
        title: title,
        url: link,
        published_at: published_at,
        translated_title: nil
      )
    end
  rescue => e
    Rails.logger.warn("Market news feed fetch failed for #{feed[:source]}: #{e.class}: #{e.message}")
    []
  end

  def self.http_get(url)
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 5

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "MaybeApp/1.0 contact@mindcont.com"
    request["Accept"] = "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8"
    request["From"] = "contact@mindcont.com" if uri.host.include?("sec.gov")
    request["Referer"] = "https://www.sec.gov/" if uri.host.include?("sec.gov")

    http.request(request)
  end

  def self.normalize_text(text)
    CGI.unescapeHTML(text.to_s).gsub(/\s+/, " ").strip
  end

  def self.fetch_all_feeds
    FEEDS.flat_map { |feed| fetch_feed(feed) }
         .sort_by { |item| item.published_at || Time.at(0) }
         .reverse
         .first(ITEM_LIMIT)
  end

  private_class_method :fetch_feed, :http_get, :normalize_text, :fetch_all_feeds
end
