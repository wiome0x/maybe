class User < ApplicationRecord
  has_secure_password

  belongs_to :family
  belongs_to :last_viewed_chat, class_name: "Chat", optional: true
  has_many :sessions, dependent: :destroy
  has_many :chats, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :mobile_devices, dependent: :destroy
  has_one :bark_notification_subscription, dependent: :destroy
  has_many :bark_notifications, dependent: :destroy
  has_one :weekly_report_subscription, dependent: :destroy
  has_many :weekly_reports, dependent: :destroy
  has_many :invitations, foreign_key: :inviter_id, dependent: :destroy
  has_many :impersonator_support_sessions, class_name: "ImpersonationSession", foreign_key: :impersonator_id, dependent: :destroy
  has_many :impersonated_support_sessions, class_name: "ImpersonationSession", foreign_key: :impersonated_id, dependent: :destroy
  accepts_nested_attributes_for :family, update_only: true

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :ensure_valid_profile_image
  validates :default_period, inclusion: { in: Period::PERIODS.keys }
  normalizes :email, with: ->(email) { email.strip.downcase }
  normalizes :unconfirmed_email, with: ->(email) { email&.strip&.downcase }

  normalizes :first_name, :last_name, with: ->(value) { value.strip.presence }

  enum :role, { member: "member", admin: "admin", super_admin: "super_admin" }, validate: true

  has_one_attached :profile_image do |attachable|
    attachable.variant :thumbnail, resize_to_fill: [ 300, 300 ], convert: :webp, saver: { quality: 80 }
    attachable.variant :small, resize_to_fill: [ 72, 72 ], convert: :webp, saver: { quality: 80 }, preprocessed: true
  end

  validate :profile_image_size

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_confirmation, expires_in: 1.day do
    unconfirmed_email
  end

  def pending_email_change?
    unconfirmed_email.present?
  end

  def initiate_email_change(new_email)
    return false if new_email == email
    return false if new_email == unconfirmed_email

    if Rails.application.config.app_mode.self_hosted? && !Setting.require_email_confirmation
      update(email: new_email)
    else
      if update(unconfirmed_email: new_email)
        EmailConfirmationMailer.with(user: self).confirmation_email.deliver_later
        true
      else
        false
      end
    end
  end

  def request_impersonation_for(user_id)
    impersonated = User.find(user_id)
    impersonator_support_sessions.create!(impersonated: impersonated)
  end

  def admin?
    super_admin? || role == "admin"
  end

  def previous_session
    sessions.where.not(id: Current.session&.id).order(created_at: :desc).first
  end

  def display_name
    [ first_name, last_name ].compact.join(" ").presence || email
  end

  def initial
    (display_name&.first || email.first).upcase
  end

  def initials
    if first_name.present? && last_name.present?
      "#{first_name.first}#{last_name.first}".upcase
    else
      initial
    end
  end

  def show_ai_sidebar?
    show_ai_sidebar
  end

  def ai_available?
    !Rails.application.config.app_mode.self_hosted? || ENV["OPENAI_ACCESS_TOKEN"].present? || ENV["OPENROUTER_API_KEY"].present?
  end

  def ai_enabled?
    ai_enabled && ai_available?
  end

  # Deactivation
  validate :can_deactivate, if: -> { active_changed? && !active }
  after_update_commit :purge_later, if: -> { saved_change_to_active?(from: true, to: false) }

  def deactivate
    transaction do
      revoke_access!
      update active: false, email: deactivated_email
    end
  end

  def can_deactivate
    if admin? && family.users.count > 1
      errors.add(:base, :cannot_deactivate_admin_with_other_users)
    end
  end

  def purge_later
    UserPurgeJob.perform_later(self)
  end

  def purge
    if last_user_in_family?
      family.destroy
    else
      destroy
    end
  end

  def revoke_access!
    revoked_at = Time.current

    sessions.delete_all
    api_keys.active.update_all(revoked_at: revoked_at)

    mobile_devices.find_each do |device|
      device.revoke_all_tokens!
    end

    if defined?(Doorkeeper::AccessToken)
      Doorkeeper::AccessToken.where(resource_owner_id: id, revoked_at: nil).update_all(revoked_at: revoked_at)
    end
  end

  # MFA
  MFA_MAX_ATTEMPTS = 5
  MFA_LOCKOUT_DURATION = 15.minutes

  def setup_mfa!
    update!(
      otp_secret: ROTP::Base32.random(32),
      otp_required: false,
      otp_backup_codes: []
    )
  end

  def enable_mfa!
    codes = generate_backup_codes
    update!(
      otp_required: true,
      otp_backup_codes: codes.map { |c| BCrypt::Password.create(c) }
    )
    codes # return plaintext codes for display only
  end

  def disable_mfa!
    update!(
      otp_secret: nil,
      otp_required: false,
      otp_backup_codes: [],
      mfa_failed_attempts: 0,
      mfa_locked_until: nil
    )
  end

  def mfa_locked?
    mfa_locked_until.present? && mfa_locked_until > Time.current
  end

  def verify_otp?(code)
    return false if otp_secret.blank?
    return false if mfa_locked?

    if verify_backup_code?(code) || verify_totp_code?(code)
      reset_mfa_failed_attempts!
      true
    else
      record_mfa_failed_attempt!
      false
    end
  end

  def provisioning_uri
    return nil unless otp_secret.present?
    totp.provisioning_uri(email)
  end

  def onboarded?
    onboarded_at.present?
  end

  def needs_onboarding?
    !onboarded?
  end

  private
    def ensure_valid_profile_image
      return unless profile_image.attached?

      unless profile_image.content_type.in?(%w[image/jpeg image/png])
        errors.add(:profile_image, "must be a JPEG or PNG")
        profile_image.purge
      end
    end

    def last_user_in_family?
      family.users.count == 1
    end

    def deactivated_email
      email.gsub(/@/, "-deactivated-#{SecureRandom.uuid}@")
    end

    def profile_image_size
      if profile_image.attached? && profile_image.byte_size > 10.megabytes
        errors.add(:profile_image, :invalid_file_size, max_megabytes: 10)
      end
    end

    def totp
      ROTP::TOTP.new(otp_secret, issuer: ENV.fetch("APP_NAME", "Maybe Finance"))
    end

    def verify_totp_code?(code)
      return false unless code.present? && code.match?(/\A\d{6}\z/)
      totp.verify(code, drift_behind: 15, drift_ahead: 15).present?
    end

    def verify_backup_code?(code)
      return false if otp_backup_codes.blank?
      return false if code.blank?

      otp_backup_codes.each_with_index do |hashed_code, index|
        if BCrypt::Password.new(hashed_code) == code
          remaining_codes = otp_backup_codes.dup
          remaining_codes.delete_at(index)
          update_column(:otp_backup_codes, remaining_codes)
          return true
        end
      end

      false
    rescue BCrypt::Errors::InvalidHash
      # Legacy plaintext codes fallback
      if (index = otp_backup_codes.index(code))
        remaining_codes = otp_backup_codes.dup
        remaining_codes.delete_at(index)
        update_column(:otp_backup_codes, remaining_codes)
        true
      else
        false
      end
    end

    def record_mfa_failed_attempt!
      new_count = mfa_failed_attempts + 1
      attrs = { mfa_failed_attempts: new_count }
      attrs[:mfa_locked_until] = MFA_LOCKOUT_DURATION.from_now if new_count >= MFA_MAX_ATTEMPTS
      update_columns(attrs)
    end

    def reset_mfa_failed_attempts!
      update_columns(mfa_failed_attempts: 0, mfa_locked_until: nil) if mfa_failed_attempts > 0
    end

    def generate_backup_codes
      8.times.map { SecureRandom.hex(4) }
    end
end
