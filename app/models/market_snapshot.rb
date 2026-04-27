class MarketSnapshot < ApplicationRecord
  ITEM_TYPES = %w[stock etf].freeze

  validates :symbol, :date, :item_type, presence: true
  validates :symbol, uniqueness: { scope: :date, case_sensitive: false }
  validates :item_type, inclusion: { in: ITEM_TYPES }

  scope :for_date,  ->(date) { where(date: date) }
  scope :stocks,    -> { where(item_type: "stock") }
  scope :etfs,      -> { where(item_type: "etf") }
  scope :recent,    -> { order(date: :desc) }
end
