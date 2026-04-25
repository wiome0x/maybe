class BrokerConnectionsController < ApplicationController
  before_action :set_broker_connection, only: %i[destroy reauth reconnect]

  def new
    @account = Current.family.accounts.find(params[:account_id])
  end

  def create
    @account = Current.family.accounts.find(broker_connection_account_id)

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
    redirect_to account_path(@account), notice: "Binance account connected successfully."
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

    @account = Current.family.accounts.find(params[:state] || params[:account_id])

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
    redirect_to account_path(@account), notice: "Charles Schwab account connected successfully."
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

    if @broker_connection.schwab?
      @schwab_authorization_url = Provider::Schwab.authorization_url(state: @broker_connection.id)
      render :reauth
    else
      render :reauth
    end
  end

  def reconnect
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

    redirect_to account_path(@broker_connection.account), notice: "Broker connection reauthorized successfully."
  rescue Provider::Error => e
    redirect_to reauth_broker_connection_path(@broker_connection), alert: "Reauthorization failed: #{e.message}"
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
      broker_connection_attributes.fetch(:account_id)
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
end
