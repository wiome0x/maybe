class BrokerOnboarding
  def initialize(session:)
    @session = session
  end

  def start_direct_connection!(family:, accountable_type:, account_name:)
    account = family.accounts.create!(
      name: account_name,
      balance: 0,
      cash_balance: 0,
      currency: family.currency,
      accountable: accountable_type.new,
      status: "draft"
    )
    account.lock_saved_attributes!
    account
  end

  def prepare_return_to!(account:, incoming_return_to:, fallback:)
    target = sanitize_local_path(incoming_return_to) || fallback
    session[session_key_for(account)] = target
    target
  end

  def authorization_state_for(account:, return_to:)
    self.class.verifier.generate(
      account_id: account.id,
      return_to: sanitize_local_path(return_to)
    )
  end

  def resolve_state(state)
    payload = self.class.verifier.verify(state)

    {
      account_id: payload[:account_id] || payload["account_id"],
      return_to: sanitize_local_path(payload[:return_to] || payload["return_to"])
    }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    {}
  end

  def success_path_for(account:, fallback:)
    session.delete(session_key_for(account)).presence || fallback
  end

  private
    attr_reader :session

    def session_key_for(account)
      "broker_onboarding:return_to:#{account.id}"
    end

    def sanitize_local_path(path)
      return nil if path.blank?

      uri = URI.parse(path)
      uri.host.nil? ? path : nil
    rescue URI::InvalidURIError
      nil
    end

    def self.verifier
      @verifier ||= Rails.application.message_verifier("broker_onboarding")
    end
end
