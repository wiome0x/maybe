class ApiRequestLog < ApplicationRecord
  include ApiRequestLog::StatsAggregator

  validates :provider_name, :request_status, :requested_at, presence: true
  validates :request_status, inclusion: { in: %w[success error] }

  scope :in_period, ->(start_date, end_date) {
    where(requested_at: start_date.beginning_of_day..end_date.end_of_day)
  }
  scope :by_provider, ->(name) { where(provider_name: name) if name.present? }
  scope :errors, -> { where(request_status: "error") }
  scope :successes, -> { where(request_status: "success") }
  scope :recent, -> { order(requested_at: :desc) }
end
