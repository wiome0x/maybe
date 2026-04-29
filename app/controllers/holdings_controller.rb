class HoldingsController < ApplicationController
  before_action :set_holding, only: %i[show destroy]

  def index
    @account = Current.family.accounts.find(params[:account_id])
  end

  def show
    @price_series = @holding.security.historical_prices
      .where(family: Current.family)
      .ordered_by_date
      .last(365)

    closes_by_date = @price_series.index_by(&:date)
    sorted_dates = closes_by_date.keys.sort

    @trade_markers = @holding.trades.filter_map do |trade_entry|
      marker_date = sorted_dates.select { |d| d <= trade_entry.date }.last
      next unless marker_date

      {
        date: marker_date.iso8601,
        close: closes_by_date[marker_date].close.to_f,
        kind: trade_entry.trade.qty.negative? ? "sell" : "buy"
      }
    end
  end

  def destroy
    if @holding.account.plaid_account_id.present?
      flash[:alert] = "You cannot delete this holding"
    else
      @holding.destroy_holding_and_entries!
      flash[:notice] = t(".success")
    end

    respond_to do |format|
      format.html { redirect_back_or_to account_path(@holding.account) }
      format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, account_path(@holding.account)) }
    end
  end

  private
    def set_holding
      @holding = Current.family.holdings.find(params[:id])
    end
end
