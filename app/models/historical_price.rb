class HistoricalPrice < ApplicationRecord
  belongs_to :family
  belongs_to :security
  belongs_to :import, class_name: "Import", optional: true

  validates :date, presence: true
  validates :close, presence: true, numericality: true
  validates :ticker, presence: true
  validates :date, uniqueness: { scope: %i[family_id security_id] }

  scope :by_ticker, ->(ticker) { where(ticker: ticker.upcase) }
  scope :by_date_range, ->(start_date, end_date) {
    scope = all
    scope = scope.where(date: start_date..) if start_date.present?
    scope = scope.where(date: ..end_date) if end_date.present?
    scope
  }
  scope :ordered_by_date, -> { order(date: :asc) }
end
