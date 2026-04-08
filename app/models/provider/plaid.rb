class Provider::Plaid
  attr_reader :client, :region

  MAYBE_SUPPORTED_PLAID_PRODUCTS = %w[transactions investments liabilities].freeze
  MAX_HISTORY_DAYS = Rails.env.development? ? 90 : 730
  REDACTED_KEYS = %w[
    access_token
    public_token
    verification_header
    plaid_verification
    authorization
    secret
    client_id
  ].freeze

  def initialize(config, region: :us)
    @client = Plaid::PlaidApi.new(
      Plaid::ApiClient.new(config)
    )
    @region = region
  end

  def validate_webhook!(verification_header, raw_body)
    audited_call(
      endpoint: "webhook_verification",
      request_payload: {
        verification_header: verification_header,
        body: parse_json_or_raw(raw_body)
      },
      source: "webhook_validation"
    ) do
      jwks_loader = ->(options) do
        key_id = options[:kid]

        jwk_response = client.webhook_verification_key_get(
          Plaid::WebhookVerificationKeyGetRequest.new(key_id: key_id)
        )

        jwks = JWT::JWK::Set.new([ jwk_response.key.to_hash ])

        jwks.filter! { |key| key[:use] == "sig" }
        jwks
      end

      payload, _header = JWT.decode(
        verification_header, nil, true,
        {
          algorithms: [ "ES256" ],
          jwks: jwks_loader,
          verify_expiration: false
        }
      )

      issued_at = Time.at(payload["iat"])
      raise JWT::VerificationError, "Webhook is too old" if Time.now - issued_at > 5.minutes

      expected_hash = payload["request_body_sha256"]
      actual_hash = Digest::SHA256.hexdigest(raw_body)
      raise JWT::VerificationError, "Invalid webhook body hash" unless ActiveSupport::SecurityUtils.secure_compare(expected_hash, actual_hash)

      payload
    end
  end

  def get_link_token(user_id:, webhooks_url:, redirect_url:, accountable_type: nil, access_token: nil)
    request_params = {
      user: { client_user_id: user_id },
      client_name: ENV.fetch("APP_NAME", "Maybe Finance"),
      country_codes: country_codes,
      language: "en",
      webhook: webhooks_url,
      redirect_uri: redirect_url,
      transactions: { days_requested: MAX_HISTORY_DAYS }
    }

    if access_token.present?
      request_params[:access_token] = access_token
    else
      request_params[:products] = [ get_primary_product(accountable_type) ]
      request_params[:additional_consented_products] = get_additional_consented_products(accountable_type)
    end

    request = Plaid::LinkTokenCreateRequest.new(request_params)

    audited_call(
      endpoint: "link_token_create",
      request_payload: request_params,
      access_token: access_token
    ) do
      client.link_token_create(request)
    end
  end

  def exchange_public_token(token)
    request = Plaid::ItemPublicTokenExchangeRequest.new(
      public_token: token
    )

    audited_call(
      endpoint: "item_public_token_exchange",
      request_payload: request.to_hash
    ) do
      client.item_public_token_exchange(request)
    end
  end

  def get_item(access_token)
    request = Plaid::ItemGetRequest.new(access_token: access_token)
    audited_call(
      endpoint: "item_get",
      request_payload: request.to_hash,
      access_token: access_token
    ) do
      client.item_get(request)
    end
  end

  def remove_item(access_token)
    request = Plaid::ItemRemoveRequest.new(access_token: access_token)
    audited_call(
      endpoint: "item_remove",
      request_payload: request.to_hash,
      access_token: access_token
    ) do
      client.item_remove(request)
    end
  end

  def get_item_accounts(access_token)
    request = Plaid::AccountsGetRequest.new(access_token: access_token)
    audited_call(
      endpoint: "accounts_get",
      request_payload: request.to_hash,
      access_token: access_token
    ) do
      client.accounts_get(request)
    end
  end

  def get_transactions(access_token, next_cursor: nil)
    cursor = next_cursor
    added = []
    modified = []
    removed = []
    has_more = true

    while has_more
      request = Plaid::TransactionsSyncRequest.new(
        access_token: access_token,
        cursor: cursor,
        options: {
          include_original_description: true
        }
      )

      response = audited_call(
        endpoint: "transactions_sync",
        request_payload: request.to_hash,
        access_token: access_token
      ) do
        client.transactions_sync(request)
      end

      added += response.added
      modified += response.modified
      removed += response.removed
      has_more = response.has_more
      cursor = response.next_cursor
    end

    TransactionSyncResponse.new(added:, modified:, removed:, cursor:)
  end

  def get_item_investments(access_token, start_date: nil, end_date: Date.current)
    start_date = start_date || MAX_HISTORY_DAYS.days.ago.to_date
    holdings, holding_securities = get_item_holdings(access_token: access_token)
    transactions, transaction_securities = get_item_investment_transactions(access_token: access_token, start_date:, end_date:)

    merged_securities = ((holding_securities || []) + (transaction_securities || [])).uniq { |s| s.security_id }

    InvestmentsResponse.new(holdings:, transactions:, securities: merged_securities)
  end

  def get_item_liabilities(access_token)
    request = Plaid::LiabilitiesGetRequest.new({ access_token: access_token })
    response = audited_call(
      endpoint: "liabilities_get",
      request_payload: request.to_hash,
      access_token: access_token
    ) do
      client.liabilities_get(request)
    end
    response.liabilities
  end

  def get_institution(institution_id)
    request = Plaid::InstitutionsGetByIdRequest.new({
      institution_id: institution_id,
      country_codes: country_codes,
      options: {
        include_optional_metadata: true
      }
    })
    audited_call(
      endpoint: "institutions_get_by_id",
      request_payload: request.to_hash
    ) do
      client.institutions_get_by_id(request)
    end
  end

  private
    TransactionSyncResponse = Struct.new :added, :modified, :removed, :cursor, keyword_init: true
    InvestmentsResponse = Struct.new :holdings, :transactions, :securities, keyword_init: true

    def get_item_holdings(access_token:)
      request = Plaid::InvestmentsHoldingsGetRequest.new({ access_token: access_token })
      response = audited_call(
        endpoint: "investments_holdings_get",
        request_payload: request.to_hash,
        access_token: access_token
      ) do
        client.investments_holdings_get(request)
      end

      [ response.holdings, response.securities ]
    end

    def get_item_investment_transactions(access_token:, start_date:, end_date:)
      transactions = []
      securities = []
      offset = 0

      loop do
        request = Plaid::InvestmentsTransactionsGetRequest.new(
          access_token: access_token,
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          options: { offset: offset }
        )

        response = audited_call(
          endpoint: "investments_transactions_get",
          request_payload: request.to_hash,
          access_token: access_token
        ) do
          client.investments_transactions_get(request)
        end

        transactions += response.investment_transactions
        securities += response.securities

        break if transactions.length >= response.total_investment_transactions
        offset = transactions.length
      end

      [ transactions, securities ]
    end

    def get_primary_product(accountable_type)
      return "transactions" if eu?

      case accountable_type
      when "Investment"
        "investments"
      when "CreditCard", "Loan"
        "liabilities"
      else
        "transactions"
      end
    end

    def get_additional_consented_products(accountable_type)
      return [] if eu?

      MAYBE_SUPPORTED_PLAID_PRODUCTS - [ get_primary_product(accountable_type) ]
    end

    def eu?
      region.to_sym == :eu
    end

    def country_codes
      if eu?
        [ "ES", "NL", "FR", "IE", "DE", "IT", "PL", "DK", "NO", "SE", "EE", "LT", "LV", "PT", "BE" ]  # EU supported countries
      else
        [ "US", "CA" ] # US + CA only
      end
    end

    def audited_call(endpoint:, request_payload:, access_token: nil, source: "api_call")
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      requested_at = Time.current

      response = yield
      duration_ms = elapsed_ms(started_at)

      create_api_log!(
        endpoint: endpoint,
        source: source,
        success: true,
        duration_ms: duration_ms,
        plaid_item_id: plaid_item_id_from(access_token),
        request_payload: redact_sensitive(request_payload),
        response_payload: redact_sensitive(serialize_response(response)),
        plaid_request_id: extract_request_id(response),
        requested_at: requested_at
      )

      response
    rescue Plaid::ApiError => e
      duration_ms = elapsed_ms(started_at)

      create_api_log!(
        endpoint: endpoint,
        source: source,
        success: false,
        duration_ms: duration_ms,
        plaid_item_id: plaid_item_id_from(access_token),
        request_payload: redact_sensitive(request_payload),
        error_payload: redact_sensitive(parse_json_or_raw(e.response_body)),
        http_status: e.code,
        requested_at: requested_at
      )
      raise
    rescue => e
      duration_ms = elapsed_ms(started_at)

      create_api_log!(
        endpoint: endpoint,
        source: source,
        success: false,
        duration_ms: duration_ms,
        plaid_item_id: plaid_item_id_from(access_token),
        request_payload: redact_sensitive(request_payload),
        error_payload: { "class" => e.class.name, "message" => e.message },
        requested_at: requested_at
      )
      raise
    end

    def create_api_log!(endpoint:, source:, success:, duration_ms:, plaid_item_id:, request_payload:, requested_at:, response_payload: {}, error_payload: {}, http_status: nil, plaid_request_id: nil)
      PlaidApiLog.create!(
        plaid_item_id: plaid_item_id,
        region: region.to_s,
        source: source,
        endpoint: endpoint,
        success: success,
        duration_ms: duration_ms,
        http_status: http_status,
        plaid_request_id: plaid_request_id,
        request_payload: request_payload || {},
        response_payload: response_payload || {},
        error_payload: error_payload || {},
        requested_at: requested_at
      )
    rescue => e
      Rails.logger.error("[Provider::Plaid] Failed to write PlaidApiLog: #{e.class} - #{e.message}")
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def plaid_item_id_from(access_token)
      return nil if access_token.blank?

      PlaidItem.find_by(access_token: access_token)&.id
    rescue => e
      Rails.logger.warn("[Provider::Plaid] Failed to resolve plaid_item by access_token: #{e.class} - #{e.message}")
      nil
    end

    def parse_json_or_raw(value)
      return {} if value.blank?
      return value if value.is_a?(Hash) || value.is_a?(Array)

      JSON.parse(value)
    rescue JSON::ParserError
      { "_raw" => value.to_s }
    end

    def serialize_response(response)
      case response
      when Hash, Array
        response
      else
        response.respond_to?(:to_hash) ? response.to_hash : { "value" => response.to_s }
      end
    end

    def extract_request_id(response)
      return nil unless response.respond_to?(:to_hash)

      response_hash = response.to_hash
      response_hash["request_id"] || response_hash.dig("item", "request_id")
    rescue
      nil
    end

    def redact_sensitive(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, v), sanitized|
          sanitized[key] = sensitive_key?(key) ? "[REDACTED]" : redact_sensitive(v)
        end
      when Array
        value.map { |v| redact_sensitive(v) }
      else
        value
      end
    end

    def sensitive_key?(key)
      REDACTED_KEYS.include?(key.to_s.downcase)
    end
end
