class WatchlistItem < ApplicationRecord
  belongs_to :family

  ITEM_TYPES = %w[stock crypto].freeze

  DEFAULT_STOCKS = [
    { symbol: "AAPL",  name: "Apple" },
    { symbol: "MSFT",  name: "Microsoft" },
    { symbol: "GOOGL", name: "Alphabet" },
    { symbol: "AMZN",  name: "Amazon" },
    { symbol: "NVDA",  name: "NVIDIA" },
    { symbol: "META",  name: "Meta Platforms" },
    { symbol: "TSLA",  name: "Tesla" },
    { symbol: "QQQM",  name: "Invesco NASDAQ 100 ETF" },
    { symbol: "VOO",   name: "Vanguard S&P 500 ETF" }
  ].freeze

  DEFAULT_CRYPTOS = [
    { symbol: "BTC",  name: "Bitcoin" },
    { symbol: "ETH",  name: "Ethereum" },
    { symbol: "BNB",  name: "BNB" },
    { symbol: "SOL",  name: "Solana" },
    { symbol: "XRP",  name: "Ripple" },
    { symbol: "ADA",  name: "Cardano" },
    { symbol: "DOGE", name: "Dogecoin" },
    { symbol: "DOT",  name: "Polkadot" }
  ].freeze

  validates :symbol, presence: true
  validates :item_type, presence: true, inclusion: { in: ITEM_TYPES }
  validates :symbol, uniqueness: { scope: [ :family_id, :item_type ], case_sensitive: false }

  before_validation :upcase_symbol

  scope :stocks, -> { where(item_type: "stock") }
  scope :cryptos, -> { where(item_type: "crypto") }
  scope :ordered, -> { order(:position, :created_at) }

  class << self
    def seed_defaults_for(family)
      return if family.watchlist_items.any?

      items = []

      DEFAULT_STOCKS.each_with_index do |stock, i|
        items << { family_id: family.id, symbol: stock[:symbol], name: stock[:name], item_type: "stock", position: i }
      end

      DEFAULT_CRYPTOS.each_with_index do |crypto, i|
        items << { family_id: family.id, symbol: crypto[:symbol], name: crypto[:name], item_type: "crypto", position: i }
      end

      insert_all(items)
    end
  end

  private
    def upcase_symbol
      self.symbol = symbol&.upcase if item_type == "stock"
    end
end
