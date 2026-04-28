class ScheduledJobRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  validates :job_name, :run_date, :status, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent,        -> { order(run_date: :desc, started_at: :desc) }
  scope :for_job,       ->(name) { where(job_name: name) }
  scope :completed,     -> { where(status: "completed") }
  scope :failed,        -> { where(status: "failed") }
  scope :in_date_range, ->(start_date, end_date) { where(run_date: start_date..end_date) }

  def duration_seconds
    return nil unless started_at && finished_at
    (finished_at - started_at).round
  end

  def success_rate
    return nil if symbols_requested.nil? || symbols_requested.zero?
    (symbols_succeeded.to_f / symbols_requested * 100).round(1)
  end
end
