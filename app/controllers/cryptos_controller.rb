class CryptosController < ApplicationController
  include AccountableResource

  def connect
    @account = broker_onboarding.start_direct_connection!(
      family: Current.family,
      accountable_type: Crypto,
      account_name: "Binance"
    )

    redirect_to new_broker_connection_path(account_id: @account.id, return_to: params[:return_to]), notice: t("accounts.create.success", type: "Crypto")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_crypto_path(step: "method_select", return_to: params[:return_to]), alert: e.message
  end

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    return_to = account_params[:return_to]
    safe_target = return_to.present? && URI.parse(return_to).host.nil? ? return_to : @account

    redirect_to safe_target, notice: t("accounts.create.success", type: "Crypto")
  rescue ActiveRecord::RecordInvalid => e
    @error_message = e.message
    render :new, status: :unprocessable_entity
  end

  private
    def broker_onboarding
      @broker_onboarding ||= BrokerOnboarding.new(session: session)
    end
end
