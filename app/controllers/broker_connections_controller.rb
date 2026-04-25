class BrokerConnectionsController < ApplicationController
  before_action :set_broker_connection, only: %i[destroy reauth reconnect]

  def new
    @account = Current.family.accounts.find(params[:account_id])
    @return_to = broker_onboarding.prepare_return_to!(account: @account, incoming_return_to: params[:return_to], fallback: account_path(@account))
    @schwab_authorization_url = Provider::Schwab.authorization_url(state: broker_onboarding.authorization_state_for(account: @account, return_to: @return_to)) if @account.investment?
  end

  def create
    @account = Current.family.accounts.find(broker_connection_account_id)
    @return_to = broker_onboarding.prepare_return_to!(account: @account, incoming_return_to: params[:return_to], fallback: account_path(@account))

    provider = Provider::Binance.new(
      api_key: broker_connection_api_key,
      api_secret: broker_connection_api_secret
    )

    provider.validate_credentials!

    @broker_connection = @account.build_broker_connection(
      family: Current.family,
      provider: "binance",
      status: "active",
      connected_at: Time.current,
      api_key: broker_connection_api_key,
      api_secret: broker_connection_api_secret
    )

    @broker_connection.save!
    @broker_connection.sync_later
    activate_account_if_draft!(@account)
    redirect_to broker_onboarding.success_path_for(account: @account, fallback: account_path(@account)), notice: "Binance account connected successfully."
  rescue Provider::Error => e
    @error_message = e.message
    @api_key = broker_connection_api_key
    render :new, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    @error_message = e.message
    @api_key = broker_connection_api_key
    render :new, status: :unprocessable_entity
  end

  def schwab_callback
    code = params[:code]
    result = Provider::Schwab.exchange_code(code: code)
    state_data = broker_onboarding.resolve_state(params[:state])

    @account = Current.family.accounts.find(state_data[:account_id] || params[:account_id] || params[:state])
    broker_onboarding.prepare_return_to!(account: @account, incoming_return_to: state_data[:return_to], fallback: account_path(@account))

    @broker_connection = @account.build_broker_connection(
      family: Current.family,
      provider: "schwab",
      status: "active",
      connected_at: Time.current,
      access_token: result[:access_token],
      refresh_token: result[:refresh_token],
      token_expires_at: Time.current + result[:expires_in].to_i.seconds,
      broker_account_id: result[:broker_account_id]
    )

    @broker_connection.save!
    @broker_connection.sync_later
    activate_account_if_draft!(@account)
    redirect_to broker_onboarding.success_path_for(account: @account, fallback: account_path(@account)), notice: "Charles Schwab account connected successfully."
  rescue Provider::Error, ActiveRecord::RecordInvalid => e
    redirect_to accounts_path, alert: "Failed to connect Schwab account: #{e.message}"
  end

  def destroy
    account = @broker_connection.account
    @broker_connection.destroy!

    respond_to do |format|
      format.html { redirect_to account_path(account), notice: "Broker connection removed." }
      format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, account_path(account)) }
    end
  end

  def reauth
    @account = @broker_connection.account
    @return_to = broker_onboarding.prepare_return_to!(account: @account, incoming_return_to: params[:return_to], fallback: account_path(@account))

    if @broker_connection.schwab?
      @schwab_authorization_url = Provider::Schwab.authorization_url(state: broker_onboarding.authorization_state_for(account: @account, return_to: @return_to))
      render :reauth
    else
      render :reauth
    end
  end

  def reconnect
    @return_to = broker_onboarding.prepare_return_to!(account: @broker_connection.account, incoming_return_to: params[:return_to], fallback: account_path(@broker_connection.account))

    if @broker_connection.binance?
      provider = Provider::Binance.new(
        api_key: reconnect_params[:api_key],
        api_secret: reconnect_params[:api_secret]
      )
      provider.validate_credentials!

      @broker_connection.update!(
        api_key: reconnect_params[:api_key],
        api_secret: reconnect_params[:api_secret],
        status: "active",
        error_message: nil
      )
    else
      result = Provider::Schwab.exchange_code(code: params[:code])

      @broker_connection.update!(
        access_token: result[:access_token],
        refresh_token: result[:refresh_token],
        token_expires_at: Time.current + result[:expires_in].to_i.seconds,
        status: "active",
        error_message: nil
      )
    end

    @broker_connection.sync_later
    activate_account_if_draft!(@broker_connection.account)

    redirect_to broker_onboarding.success_path_for(account: @broker_connection.account, fallback: account_path(@broker_connection.account)), notice: "Broker connection reauthorized successfully."
  rescue Provider::Error => e
    redirect_to reauth_broker_connection_path(@broker_connection, return_to: @return_to), alert: "Reauthorization failed: #{e.message}"
  end

  private

    def broker_connection_attributes
      @broker_connection_attributes ||= params.require(:broker_connection)
    end

    def set_broker_connection
      @broker_connection = BrokerConnection.find_by!(
        id: params[:id],
        family: Current.family
      )
    rescue ActiveRecord::RecordNotFound
      head :not_found
    end

    def broker_connection_account_id
      broker_connection_attributes[:account_id].presence || params.fetch(:account_id)
    end

    def broker_connection_api_key
      broker_connection_attributes.fetch(:api_key)
    end

    def broker_connection_api_secret
      broker_connection_attributes.fetch(:api_secret)
    end

    def reconnect_params
      params.require(:broker_connection).permit(:api_key, :api_secret)
    end

    def activate_account_if_draft!(account)
      account.activate! if account.draft?
    end

    def broker_onboarding
      @broker_onboarding ||= BrokerOnboarding.new(session: session)
    end
end
