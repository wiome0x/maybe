class BarkNotificationSubscription < ApplicationRecord
  DELIVERY_FREQUENCIES = %w[realtime hourly_digest daily_digest].freeze
  PUSH_CATEGORIES = %w[market_news weekly_report system_alerts].freeze

  belongs_to :user

  validates :delivery_frequency, inclusion: { in: DELIVERY_FREQUENCIES }
  validates :digest_hour, inclusion: { in: 0..23 }
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map { |tz| tz.tzinfo.identifier } }
  validates :user_id, uniqueness: true
  validate :push_categories_supported

  before_validation :apply_defaults
  before_validation :normalize_fields

  scope :enabled, -> { where(enabled: true) }

  def configured?
    device_key.present? && server_url.present?
  end

  def wants_category?(category)
    push_categories.include?(category.to_s)
  end

  def scheduled_for(occurred_at: Time.current)
    local_time = occurred_at.in_time_zone(timezone)

    scheduled_local =
      case delivery_frequency
      when "realtime"
        local_time
      when "hourly_digest"
        local_time.beginning_of_hour + 1.hour
      when "daily_digest"
        slot = local_time.change(hour: digest_hour, min: 0, sec: 0)
        local_time < slot ? slot : slot + 1.day
      else
        local_time
      end

    scheduled_local.utc
  end

  def batch_key_for(category:, source_key:, occurred_at: Time.current)
    return source_key if delivery_frequency == "realtime"

    "#{category}:#{scheduled_for(occurred_at: occurred_at).iso8601}"
  end

  private
    def apply_defaults
      self.enabled = false if enabled.nil?
      self.server_url = BarkNotifier::DEFAULT_SERVER_URL if server_url.blank?
      self.push_categories = %w[market_news weekly_report] if push_categories.blank?
      self.delivery_frequency ||= "realtime"
      self.digest_hour = 8 if digest_hour.nil?
      self.timezone ||= user&.family&.timezone || Time.zone.tzinfo.identifier
    end

    def normalize_fields
      self.server_url = server_url.to_s.strip.chomp("/")
      self.device_key = device_key.to_s.strip.presence
      self.group_name = group_name.to_s.strip.presence
      self.sound = sound.to_s.strip.presence
      self.icon = icon.to_s.strip.presence
      self.push_categories = Array(push_categories).reject(&:blank?).uniq
    end

    def push_categories_supported
      invalid = push_categories - PUSH_CATEGORIES
      return if invalid.empty?

      errors.add(:push_categories, "contains unsupported values: #{invalid.join(', ')}")
    end
end
