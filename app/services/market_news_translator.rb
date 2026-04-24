require "digest"
require "json"
require "net/http"

class MarketNewsTranslator
  CACHE_TTL = 12.hours

  def self.translate_items(items, locale:)
    return items unless locale.to_s.start_with?("zh")
    return items if api_key.blank?

    items.map do |item|
      translated_title = translate_text(item.title)
      next item if translated_title.blank? || translated_title == item.title

      item.with(translated_title: translated_title)
    end
  end

  def self.translate_text(text)
    normalized = text.to_s.strip
    return normalized if normalized.blank?

    Rails.cache.fetch(cache_key(normalized), expires_in: CACHE_TTL) do
      request_translation(normalized) || normalized
    end
  rescue => e
    Rails.logger.warn("Market news translation failed: #{e.class}: #{e.message}")
    normalized
  end

  def self.request_translation(text)
    uri = URI("https://api-free.deepl.com/v2/translate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "DeepL-Auth-Key #{api_key}"
    request["Content-Type"] = "application/json"
    request.body = {
      text: [ text ],
      target_lang: "ZH",
      preserve_formatting: true
    }.to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("DeepL translation failed: HTTP #{response.code}")
      return nil
    end

    JSON.parse(response.body).dig("translations", 0, "text")&.strip
  end

  def self.cache_key(text)
    "markets/news_translation:v1:#{Digest::SHA256.hexdigest(text)}"
  end

  def self.api_key
    ENV["DEEPL_API_KEY"].presence
  end

  private_class_method :request_translation, :cache_key, :api_key
end
