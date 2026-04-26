class SecurityDetailsJob < ApplicationJob
  queue_as :low_priority

  def perform(security_id)
    security = Security.find_by(id: security_id)
    return unless security

    # Try Synth first (if configured)
    security.import_provider_details
    return if security.reload.logo_url.present?

    # Fallback: CoinGecko search (free, no API key required)
    fetch_crypto_logo(security)
  end

  private

    def fetch_crypto_logo(security)
      coingecko = Provider::Coingecko.new
      result = coingecko.search_coins(security.ticker)
      return unless result.success?

      match = result.data.find { |c| c[:symbol]&.upcase == security.ticker.upcase }
      return unless match&.dig(:logo_url).present?

      security.update(logo_url: match[:logo_url])
    rescue => e
      Rails.logger.warn("[SecurityDetailsJob] Failed to fetch logo for #{security.ticker}: #{e.message}")
    end
end
