require "digest"
require "json"
require "net/http"

class MarketNewsTranslator
  CACHE_TTL = 12.hours

  def self.translate_items(items, locale:)
    return items unless locale.to_s.start_with?("zh")
    return items if azure_config_missing?

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
      request_translation_with_azure(normalized) || normalized
    end
  rescue => e
    Rails.logger.warn("Market news translation failed: #{e.class}: #{e.message}")
    normalized
  end

  def self.request_translation_with_azure(text)
    uri = URI("#{azure_endpoint}/translate")
    uri.query = URI.encode_www_form(
      "api-version" => "3.0",
      "to" => "zh-Hans"
    )

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 2
    http.read_timeout = 5

    request = Net::HTTP::Post.new(uri)
    request["Ocp-Apim-Subscription-Key"] = azure_key
    request["Ocp-Apim-Subscription-Region"] = azure_region
    request["Content-Type"] = "application/json"
    request.body = [ { Text: text } ].to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("Azure translation failed: HTTP #{response.code}")
      return nil
    end

    JSON.parse(response.body).dig(0, "translations", 0, "text")&.strip
  end

  def self.cache_key(text)
    "markets/news_translation:v2:#{Digest::SHA256.hexdigest(text)}"
  end

  def self.azure_key
    ENV["AZURE_TRANSLATOR_KEY"]&.strip.presence
  end

  def self.azure_endpoint
    ENV["AZURE_TRANSLATOR_ENDPOINT"]&.strip.presence&.chomp("/")
  end

  def self.azure_region
    ENV["AZURE_TRANSLATOR_REGION"]&.strip.presence
  end

  def self.azure_config_missing?
    azure_key.blank? || azure_endpoint.blank? || azure_region.blank?
  end

  private_class_method :request_translation_with_azure, :cache_key,
    :azure_key, :azure_endpoint, :azure_region, :azure_config_missing?
end
