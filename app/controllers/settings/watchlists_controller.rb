class Settings::WatchlistsController < ApplicationController
  layout "settings"

  def show
    @stock_items = Current.family.watchlist_items.stocks.ordered
    @crypto_items = Current.family.watchlist_items.cryptos.ordered
  end

  def create
    item = Current.family.watchlist_items.new(watchlist_params)

    if item.save
      redirect_to settings_watchlist_path, notice: "#{item.symbol} added to watchlist."
    else
      redirect_to settings_watchlist_path, alert: item.errors.full_messages.join(", ")
    end
  end

  def destroy
    item = Current.family.watchlist_items.find(params[:id])
    symbol = item.symbol
    item.destroy
    redirect_to settings_watchlist_path, notice: "#{symbol} removed from watchlist."
  end

  private
    def watchlist_params
      params.require(:watchlist_item).permit(:symbol, :name, :item_type)
    end
end
