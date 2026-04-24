class Settings::WatchlistsController < ApplicationController
  layout "settings"
  before_action :ensure_watchlist_defaults, only: :show

  def show
    @stock_items = Current.family.watchlist_items.stocks.ordered
    @crypto_items = Current.family.watchlist_items.cryptos.ordered
  end

  def create
    item = Current.family.watchlist_items.new(watchlist_params)

    if item.save
      redirect_to settings_watchlist_path, notice: t(".created", symbol: item.symbol)
    else
      redirect_to settings_watchlist_path, alert: item.errors.full_messages.join(", ")
    end
  end

  def destroy
    item = Current.family.watchlist_items.find(params[:id])
    symbol = item.symbol
    item.destroy
    redirect_to settings_watchlist_path, notice: t(".removed", symbol: symbol)
  end

  def reorder
    ids = params[:item_ids] || []
    ids.each_with_index do |id, index|
      Current.family.watchlist_items.where(id: id).update_all(position: index)
    end
    head :ok
  end

  private
    def ensure_watchlist_defaults
      WatchlistItem.seed_defaults_for(Current.family)
    end

    def watchlist_params
      params.require(:watchlist_item).permit(:symbol, :name, :item_type)
    end
end
