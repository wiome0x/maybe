class PlaidApiLog < ApplicationRecord
  belongs_to :plaid_item, optional: true

  validates :region, :source, :endpoint, :requested_at, presence: true

  scope :in_period, ->(start_date, end_date) {
    where(requested_at: start_date.beginning_of_day..end_date.end_of_day)
  }
  scope :by_provider, ->(name) { where(source: name) if name.present? }
  scope :errors, -> { where(success: false) }
  scope :successes, -> { where(success: true) }
  scope :recent, -> { order(requested_at: :desc) }

  class << self
    def daily_totals(start_date:, end_date:)
      in_period(start_date, end_date)
        .group("DATE(requested_at)")
        .select("DATE(requested_at) AS date, COUNT(*) AS total,
                 COUNT(*) FILTER (WHERE success = true) AS success_count,
                 COUNT(*) FILTER (WHERE success = false) AS error_count")
        .order("date")
    end

    def provider_summary(start_date:, end_date:)
      in_period(start_date, end_date)
        .group(:source)
        .select("source AS provider_name, COUNT(*) AS total,
                 COUNT(*) FILTER (WHERE success = false) AS error_count")
        .order("total DESC")
    end

    def overview_stats(start_date:, end_date:)
      scope = in_period(start_date, end_date)
      total = scope.count
      errors = scope.errors.count
      avg_response_time = scope.average(:duration_ms)&.round(1) || 0

      {
        total_requests: total,
        total_errors: errors,
        error_rate: total > 0 ? (errors.to_f / total * 100).round(1) : 0,
        avg_response_time_ms: avg_response_time
      }
    end
  end
end
