class Provider::Registry
  include ActiveModel::Validations

  Error = Class.new(StandardError)

  CONCEPTS = %i[exchange_rates securities llm]

  validates :concept, inclusion: { in: CONCEPTS }

  class << self
    def for_concept(concept)
      new(concept.to_sym)
    end

    def get_provider(name)
      send(name)
    rescue NoMethodError
      raise Error.new("Provider '#{name}' not found in registry")
    end

    def plaid_provider_for_region(region)
      region.to_sym == :us ? plaid_us : plaid_eu
    end

    private
      def stripe
        secret_key = ENV["STRIPE_SECRET_KEY"]
        webhook_secret = ENV["STRIPE_WEBHOOK_SECRET"]

        return nil unless secret_key.present? && webhook_secret.present?

        Provider::Stripe.new(secret_key:, webhook_secret:)
      end

      def currency_api
        return nil unless ENV["EXCHANGE_RATE_PROVIDER"] == "currency_api"

        Provider::CurrencyApi.new
      end

      def synth
        api_key = ENV.fetch("SYNTH_API_KEY", Setting.synth_api_key)

        return nil unless api_key.present?

        Provider::Synth.new(api_key)
      end

      def plaid_us
        config = Rails.application.config.plaid || build_plaid_config(
          client_id: ENV["PLAID_CLIENT_ID"],
          secret: ENV["PLAID_SECRET"]
        )

        return nil unless config.present?

        Provider::Plaid.new(config, region: :us)
      end

      def plaid_eu
        config = Rails.application.config.plaid_eu || build_plaid_config(
          client_id: ENV["PLAID_EU_CLIENT_ID"],
          secret: ENV["PLAID_EU_SECRET"]
        )

        return nil unless config.present?

        Provider::Plaid.new(config, region: :eu)
      end

      def build_plaid_config(client_id:, secret:)
        return nil if client_id.blank? || secret.blank?

        Plaid::Configuration.new.tap do |config|
          config.server_index = Plaid::Configuration::Environment[ENV.fetch("PLAID_ENV", "sandbox")]
          config.api_key["PLAID-CLIENT-ID"] = client_id
          config.api_key["PLAID-SECRET"] = secret
        end
      end

      def github
        Provider::Github.new
      end

      def openai
        access_token = ENV.fetch("OPENAI_ACCESS_TOKEN", Setting.openai_access_token)

        return nil unless access_token.present?

        Provider::Openai.new(access_token)
      end

      def openrouter
        access_token = ENV["OPENROUTER_API_KEY"]

        return nil unless access_token.present?

        models = ENV.fetch("OPENROUTER_MODELS", "google/gemini-2.5-flash,anthropic/claude-sonnet-4,openai/gpt-4.1").split(",").map(&:strip)

        Provider::Openrouter.new(access_token, models: models)
      end

      def binance(broker_connection:)
        return nil if broker_connection.api_key.blank? || broker_connection.api_secret.blank?

        Provider::Binance.new(
          api_key: broker_connection.api_key,
          api_secret: broker_connection.api_secret
        )
      end

      def schwab(broker_connection:)
        return nil if broker_connection.access_token.blank?

        Provider::Schwab.new(
          access_token: broker_connection.access_token,
          refresh_token: broker_connection.refresh_token,
          broker_connection: broker_connection
        )
      end
  end

  def initialize(concept)
    @concept = concept
    validate!
  end

  def providers
    available_providers.map { |p| self.class.send(p) }
  end

  def get_provider(name)
    provider_method = available_providers.find { |p| p == name.to_sym }

    raise Error.new("Provider '#{name}' not found for concept: #{concept}") unless provider_method.present?

    self.class.send(provider_method)
  end

  private
    attr_reader :concept

    def available_providers
      case concept
      when :exchange_rates
        %i[currency_api synth]
      when :securities
        %i[synth]
      when :llm
        %i[openai openrouter]
      else
        %i[synth plaid_us plaid_eu github openai]
      end
    end
end
