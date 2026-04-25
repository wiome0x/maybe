class BarkNotification < ApplicationRecord
  CATEGORIES = BarkNotificationSubscription::PUSH_CATEGORIES

  belongs_to :user

  enum :status, {
    pending: "pending",
    sent: "sent",
    failed: "failed"
  }, validate: true

  validates :category, inclusion: { in: CATEGORIES }
  validates :source_key, :title, :body, :scheduled_for, :batch_key, presence: true
  validates :source_key, uniqueness: { scope: :user_id }

  scope :due, ->(reference_time = Time.current) { pending.where("scheduled_for <= ?", reference_time) }
  scope :scheduled_first, -> { order(:scheduled_for, :created_at) }
end
