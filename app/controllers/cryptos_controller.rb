class CryptosController < ApplicationController
  include AccountableResource

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    redirect_to new_broker_connection_path(account_id: @account.id), notice: t("accounts.create.success", type: "Crypto")
  rescue ActiveRecord::RecordInvalid => e
    @error_message = e.message
    render :new, status: :unprocessable_entity
  end
end
