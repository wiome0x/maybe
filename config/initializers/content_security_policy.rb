# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, "'unsafe-inline'"
    # Allow Plaid Link and TradingView scripts
    policy.script_src  :self, "https://cdn.plaid.com", "https://s3.tradingview.com"

    # TradingView widget loads iframes and connects to its own domains
    policy.frame_src   :self, "https://cdn.plaid.com", "https://*.tradingview.com"
    policy.connect_src :self, "wss://#{ENV['APP_DOMAIN']}", "ws://localhost:*", "https://*.tradingview.com"
  end

  # Generate session nonces for permitted importmap and inline scripts
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
