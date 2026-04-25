class InvestmentsController < ApplicationController
  include AccountableResource

  def connect
    @account = Current.family.accounts.create!(
      name: "Charles Schwab",
      balance: 0,
      cash_balance: 0,
      currency: Current.family.currency,
      accountable: Investment.new,
      status: "draft"
    )
    @account.lock_saved_attributes!

    redirect_to new_broker_connection_path(account_id: @account.id), notice: t("accounts.create.success", type: "Investment")
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_investment_path(step: "method_select", return_to: params[:return_to]), alert: e.message
  end

  def create
    @account = Current.family.accounts.create_and_sync(account_params.except(:return_to))
    @account.lock_saved_attributes!

    redirect_to new_broker_connection_path(account_id: @account.id), notice: t("accounts.create.success", type: "Investment")
  rescue ActiveRecord::RecordInvalid => e
    @error_message = e.message
    render :new, status: :unprocessable_entity
  end
end
