class WeeklyReportSubscription < ApplicationRecord
  PERIOD_KEYS = %w[last_7_days].freeze

  belongs_to :user

  validates :period_key, inclusion: { in: PERIOD_KEYS }
  validates :send_weekday, inclusion: { in: 0..6 }
  validates :send_hour, inclusion: { in: 0..23 }
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map { |tz| tz.tzinfo.identifier } }
  validates :user_id, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  before_validation :apply_defaults

  def due_for_dispatch?(reference_time: Time.current)
    return false unless enabled?

    local_time = reference_time.in_time_zone(timezone)
    local_time.wday == send_weekday && local_time.hour == send_hour
  end

  def period_for(reference_time: Time.current)
    local_date = reference_time.in_time_zone(timezone).to_date

    case period_key
    when "last_7_days"
      Period.custom(start_date: local_date - 6.days, end_date: local_date)
    else
      raise Period::InvalidKeyError, "Unsupported weekly report period key: #{period_key}"
    end
  end

  def scheduled_for(reference_time: Time.current)
    local_time = reference_time.in_time_zone(timezone)

    Time.use_zone(timezone) do
      Time.zone.local(local_time.year, local_time.month, local_time.day, send_hour, 0, 0).utc
    end
  end

  private
    def apply_defaults
      self.enabled = false if enabled.nil?
      self.period_key ||= "last_7_days"
      self.send_weekday = Date.current.wday if send_weekday.nil?
      self.send_hour ||= 8
      self.timezone ||= user&.family&.timezone || Time.zone.tzinfo.identifier
    end
end
