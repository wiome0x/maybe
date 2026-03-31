class WatchlistItem < ApplicationRecord
  belongs_to :family

  ITEM_TYPES = %w[stock crypto].freeze

  validates :symbol, presence: true
  validates :item_type, presence: true, inclusion: { in: ITEM_TYPES }
  validates :symbol, uniqueness: { scope: [ :family_id, :item_type ], case_sensitive: false }

  before_validation :upcase_symbol

  scope :stocks, -> { where(item_type: "stock") }
  scope :cryptos, -> { where(item_type: "crypto") }
  scope :ordered, -> { order(:position, :created_at) }

  private
    def upcase_symbol
      self.symbol = symbol&.upcase if item_type == "stock"
    end
end
