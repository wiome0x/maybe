class AppUrlBuilder
  def self.url_for(path)
    options = default_url_options
    return path unless options[:host].present?

    protocol = options[:protocol].presence || "https"
    port = normalized_port(options[:port], protocol)
    base = "#{protocol}://#{options[:host]}"
    base = "#{base}:#{port}" if port.present?

    "#{base}#{path}"
  end

  def self.default_url_options
    Rails.application.config.action_mailer.default_url_options&.symbolize_keys || {}
  end

  def self.normalized_port(port, protocol)
    return nil if port.blank?
    return nil if protocol == "http" && port.to_i == 80
    return nil if protocol == "https" && port.to_i == 443

    port.to_i
  end
end
