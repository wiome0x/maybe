class DispatchBarkNotificationsJob < ApplicationJob
  queue_as :scheduled

  def perform(reference_time: Time.current)
    track_run("dispatch_bark_notifications") do |run|
      count = BarkNotificationDispatcher.new(now: reference_time).dispatch_due
      run.records_written = count
    end
  end
end
