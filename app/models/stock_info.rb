class StockInfo < ApplicationRecord
  CACHE_KEY_PREFIX = "stock_info:v1".freeze
  CACHE_TTL = 7.days
  WIKIPEDIA_SYNC_TTL = 30.days

  validates :symbol, presence: true, uniqueness: true

  # Public API: returns English description string for a symbol.
  # Lookup order: Rails.cache → DB → Wikipedia (writes back to DB + cache)
  def self.description_for(symbol)
    sym = symbol.to_s.upcase.strip
    return nil if sym.blank?

    Rails.cache.fetch("#{CACHE_KEY_PREFIX}:#{sym}", expires_in: CACHE_TTL) do
      record = find_or_fetch(sym)
      record&.description_en
    end
  end

  # Returns Chinese description, falling back to English if translation unavailable
  def self.description_zh_for(symbol)
    sym = symbol.to_s.upcase.strip
    return nil if sym.blank?

    Rails.cache.fetch("#{CACHE_KEY_PREFIX}:zh:#{sym}", expires_in: CACHE_TTL) do
      record = find_or_fetch(sym)
      record&.description_zh.presence || record&.description_en
    end
  end

  # Bulk-seed all S&P 500 companies from Wikipedia (idempotent, skips existing)
  def self.sync_from_wikipedia!
    WikipediaSync.new.call
  end

  def description_en
    [ sector, sub_industry ].reject(&:blank?).uniq.join(" · ").presence
  end

  def needs_zh_translation?
    description_zh.blank? && description_en.present?
  end

  def translate_to_zh!
    return if description_en.blank?

    translated = MarketNewsTranslator.translate_text(description_en)
    # translate_text returns the original text when Azure is not configured
    return if translated.blank? || translated == description_en

    update!(description_zh: translated)
    Rails.cache.delete("#{CACHE_KEY_PREFIX}:zh:#{symbol}")
  end

  private

    def self.find_or_fetch(sym)
      record = find_by(symbol: sym)
      return record if record.present?

      # Not in DB — try to pull from Wikipedia bulk data
      WikipediaSync.new.upsert_symbol(sym)
      find_by(symbol: sym)
    end

    private_class_method :find_or_fetch

    # Inner class responsible for Wikipedia fetching and parsing
    class WikipediaSync
      WIKIPEDIA_API_URL = "https://en.wikipedia.org/w/api.php"

      def call
        data = fetch_all
        return if data.empty?

        now = Time.current
        rows = data.map do |sym, (sector, sub_industry)|
          {
            symbol: sym,
            sector: sector,
            sub_industry: sub_industry,
            wikipedia_synced_at: now,
            created_at: now,
            updated_at: now
          }
        end

        StockInfo.upsert_all(
          rows,
          unique_by: :symbol,
          update_only: %i[sector sub_industry wikipedia_synced_at]
        )

        Rails.logger.info("StockInfo: upserted #{rows.size} records from Wikipedia")
        rows.size
      end

      # Fetch Wikipedia data and upsert just one symbol (used for on-demand lookup)
      def upsert_symbol(sym)
        data = fetch_all
        return unless data.key?(sym)

        sector, sub_industry = data[sym]
        StockInfo.upsert(
          { symbol: sym, sector: sector, sub_industry: sub_industry, wikipedia_synced_at: Time.current },
          unique_by: :symbol,
          update_only: %i[sector sub_industry wikipedia_synced_at]
        )
      end

      def fetch_all
        html = fetch_wikipedia_html
        return {} if html.blank?

        parse_table(html)
      rescue => e
        Rails.logger.warn("StockInfo Wikipedia fetch failed: #{e.class}: #{e.message}")
        {}
      end

    private

      def fetch_wikipedia_html
        uri = URI(WIKIPEDIA_API_URL)
        uri.query = URI.encode_www_form(
          action: "parse",
          page: "List of S&P 500 companies",
          prop: "text",
          section: "1",
          format: "json"
        )

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 10

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "MaybeFinanceApp/1.0 (https://github.com/maybe-finance/maybe)"
        request["Accept"] = "application/json"

        response = http.request(request)
        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("Wikipedia API request failed: HTTP #{response.code}")
          return nil
        end

        JSON.parse(response.body).dig("parse", "text", "*")
      end

      def parse_table(html)
        result = {}

        table_match = html.match(/<table[^>]*wikitable[^>]*>(.*?)<\/table>/im)
        return {} unless table_match

        rows = table_match[1].scan(/<tr[^>]*>(.*?)<\/tr>/im)
        rows.each do |row_match|
          cells = row_match[0].scan(/<t[dh][^>]*>(.*?)<\/t[dh]>/im).map do |cell|
            strip_tags(cell[0]).strip
          end

          next if cells.size < 4
          next if cells[0].downcase.include?("symbol")

          symbol = cells[0].upcase.strip
          sector = cells[2].strip
          sub_industry = cells[3].strip

          next if symbol.blank?

          result[symbol] = [ sector.presence, sub_industry.presence ]
        end

        result
      end

      def strip_tags(html)
        html
          .gsub(/<[^>]+>/, "")
          .gsub(/&amp;/, "&")
          .gsub(/&lt;/, "<")
          .gsub(/&gt;/, ">")
          .gsub(/&#\d+;/, "")
          .gsub(/&[a-z]+;/, " ")
          .strip
      end
    end
end
