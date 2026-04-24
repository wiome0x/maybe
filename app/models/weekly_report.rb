class WeeklyReport < ApplicationRecord
  belongs_to :user

  enum :status, {
    pending: "pending",
    sent: "sent",
    failed: "failed",
    skipped: "skipped"
  }, default: :pending, validate: true

  validates :period_start_date, :period_end_date, :scheduled_for, :status, presence: true
  validates :period_end_date, comparison: { greater_than_or_equal_to: :period_start_date }
  validates :period_start_date, uniqueness: { scope: [ :user_id, :period_end_date ] }

  scope :ordered, -> { order(scheduled_for: :desc, created_at: :desc) }

  def payload_overview
    payload&.fetch("overview", {}) || {}
  end

  def payload_accounts
    payload&.fetch("accounts", []) || []
  end

  def recipient_email
    payload&.fetch("recipient_email", nil).presence || user.email
  end

  def all_recipient_emails
    extra = payload&.fetch("extra_recipient_emails", []) || []
    ([ recipient_email ] + extra.reject(&:blank?)).uniq
  end

  def period
    Period.custom(start_date: period_start_date, end_date: period_end_date)
  end
end
