require "test_helper"

class WatchlistItemTest < ActiveSupport::TestCase
  test "seed_defaults_for creates defaults when watchlist is empty" do
    family = families(:empty)

    assert_difference -> { family.watchlist_items.count }, WatchlistItem::DEFAULT_STOCKS.size + WatchlistItem::DEFAULT_CRYPTOS.size do
      WatchlistItem.seed_defaults_for(family)
    end
  end

  test "seed_defaults_for recreates defaults if watchlist rows are missing" do
    family = families(:empty)

    WatchlistItem.seed_defaults_for(family)
    family.watchlist_items.delete_all

    assert_difference -> { family.watchlist_items.count }, WatchlistItem::DEFAULT_STOCKS.size + WatchlistItem::DEFAULT_CRYPTOS.size do
      WatchlistItem.seed_defaults_for(family)
    end
  end
end
