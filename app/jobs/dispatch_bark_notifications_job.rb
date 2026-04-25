class DispatchBarkNotificationsJob < ApplicationJob
  queue_as :scheduled

  def perform(reference_time: Time.current)
    BarkNotificationDispatcher.new(now: reference_time).dispatch_due
  end
end
