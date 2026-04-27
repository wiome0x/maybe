class ApiRequestLogCleanupJob < ApplicationJob
  queue_as :scheduled

  def perform
    track_run("clean_api_request_logs") do |run|
      count = 0
      ApiRequestLog.where("requested_at < ?", 90.days.ago).in_batches { |batch| count += batch.delete_all }
      run.records_written = count
    end
  end
end
