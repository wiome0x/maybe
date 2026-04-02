class ApiRequestLogCleanupJob < ApplicationJob
  queue_as :scheduled

  def perform
    ApiRequestLog.where("requested_at < ?", 90.days.ago).in_batches.delete_all
  end
end
