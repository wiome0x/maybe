class BarkNotificationScheduler
  def self.enqueue!(user:, category:, title:, body:, source_key:, target_url: nil, occurred_at: Time.current, payload: {})
    subscription = user.bark_notification_subscription
    return nil unless subscription&.enabled?
    return nil unless subscription.configured?
    return nil unless subscription.wants_category?(category)

    user.bark_notifications.create_with(
      title:,
      body:,
      target_url: target_url,
      scheduled_for: subscription.scheduled_for_category(category: category, occurred_at: occurred_at),
      batch_key: subscription.batch_key_for(category:, source_key:, occurred_at: occurred_at),
      payload:
    ).find_or_create_by!(
      category: category.to_s,
      source_key:
    )
  end
end
