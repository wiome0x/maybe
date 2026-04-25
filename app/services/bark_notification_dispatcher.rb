class BarkNotificationDispatcher
  def initialize(now: Time.current, notifier_class: BarkNotifier)
    @now = now
    @notifier_class = notifier_class
  end

  def dispatch_due
    BarkNotification.due(now).scheduled_first.includes(user: :bark_notification_subscription).group_by(&:batch_key).sum do |_batch_key, notifications|
      dispatch_batch(notifications)
    end
  end

  private
    attr_reader :now, :notifier_class

    def dispatch_batch(notifications)
      subscription = notifications.first.user.bark_notification_subscription
      return 0 unless subscription&.enabled? && subscription.configured?

      notifier = notifier_class.new(subscription)
      title, body, target_url = render_payload_for(subscription, notifications)

      notifier.deliver(title:, body:, url: target_url)
      notifications.each { |notification| notification.update!(status: :sent, delivered_at: now, error_message: nil) }
      notifications.count
    rescue => error
      notifications.each { |notification| notification.update!(status: :failed, error_message: error.message.truncate(500)) }
      Rails.logger.warn("Bark notification dispatch failed for user #{notifications.first.user_id}: #{error.class}: #{error.message}")
      0
    end

    def render_payload_for(subscription, notifications)
      notification = notifications.first
      if subscription.delivery_frequency_for(notification.category) == "realtime" && notifications.one?
        return [ notification.title, notification.body, notification.target_url ]
      end

      category = notification.category
      title = digest_title(category, notifications.count)
      body = notifications.first(5).map.with_index(1) { |item, index| "#{index}. #{item.title}" }.join("\n")
      body = "#{body}\n+#{notifications.count - 5} more" if notifications.count > 5

      [ title, body, notification.target_url ]
    end

    def digest_title(category, count)
      case category
      when "market_news"
        "Market news digest (#{count})"
      when "weekly_report"
        "Weekly report updates (#{count})"
      else
        "Maybe notifications (#{count})"
      end
    end
end
