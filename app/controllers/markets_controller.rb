class MarketsController < ApplicationController
  before_action :ensure_watchlist_defaults

  def stocks
    watchlist = Current.family.watchlist_items.stocks.ordered
    @quotes = fetch_stock_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  def cryptos
    watchlist = Current.family.watchlist_items.cryptos.ordered
    @quotes = fetch_crypto_quotes(watchlist)
    @breadcrumbs = [ [ t(".home"), root_path ], [ t(".title"), nil ] ]
  end

  private
    def fetch_stock_quotes(watchlist)
      return [] if watchlist.empty?
      symbols = watchlist.pluck(:symbol)
      provider = Provider::Finnhub.new
      result = provider.fetch_market_data(symbols)
      result.success? ? result.data : []
    rescue => e
      Rails.logger.warn("Failed to fetch stock quotes: #{e.message}")
      []
    end

    def fetch_crypto_quotes(watchlist)
      return [] if watchlist.empty?
      symbols = watchlist.pluck(:symbol)
      provider = Provider::Coingecko.new
      result = provider.fetch_market_data(symbols)
      result.success? ? result.data : []
    rescue => e
      Rails.logger.warn("Failed to fetch crypto quotes: #{e.message}")
      []
    end

    def ensure_watchlist_defaults
      WatchlistItem.seed_defaults_for(Current.family)
    end
end
