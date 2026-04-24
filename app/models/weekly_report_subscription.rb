class WeeklyReportSubscription < ApplicationRecord
  PERIOD_KEYS = %w[last_7_days].freeze
  MAX_EXTRA_RECIPIENTS = 3

  belongs_to :user

  validates :period_key, inclusion: { in: PERIOD_KEYS }
  validates :send_weekday, inclusion: { in: 0..6 }
  validates :send_hour, inclusion: { in: 0..23 }
  validates :timezone, inclusion: { in: ActiveSupport::TimeZone.all.map { |tz| tz.tzinfo.identifier } }
  validates :user_id, uniqueness: true
  validate :extra_recipients_limit
  validate :extra_recipients_format

  def all_recipient_emails
    ([ user.email ] + extra_recipient_emails.reject(&:blank?)).uniq
  end

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
      self.extra_recipient_emails ||= []
    end

    def extra_recipients_limit
      return if extra_recipient_emails.blank?
      if extra_recipient_emails.reject(&:blank?).size > MAX_EXTRA_RECIPIENTS
        errors.add(:extra_recipient_emails, "最多只能添加 #{MAX_EXTRA_RECIPIENTS} 个额外收件人")
      end
    end

    def extra_recipients_format
      return if extra_recipient_emails.blank?
      extra_recipient_emails.reject(&:blank?).each do |email|
        unless email.match?(URI::MailTo::EMAIL_REGEXP)
          errors.add(:extra_recipient_emails, "#{email} 不是有效的邮箱地址")
        end
      end
    end
end
