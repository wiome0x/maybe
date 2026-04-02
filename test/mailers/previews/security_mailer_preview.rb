# Preview all emails at http://localhost:3000/rails/mailers/security_mailer
class SecurityMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/security_mailer/new_device_login
  def new_device_login
    user = User.first
    session = user.sessions.first || OpenStruct.new(
      ip_address: "203.0.113.42",
      user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
      created_at: Time.current
    )

    SecurityMailer.new_device_login(user, session)
  end

  # Preview this email at http://localhost:3000/rails/mailers/security_mailer/password_changed
  def password_changed
    user = User.first
    SecurityMailer.password_changed(user)
  end

  # Preview this email at http://localhost:3000/rails/mailers/security_mailer/mfa_status_changed_enabled
  def mfa_status_changed_enabled
    user = User.first
    SecurityMailer.mfa_status_changed(user, enabled: true)
  end

  # Preview this email at http://localhost:3000/rails/mailers/security_mailer/mfa_status_changed_disabled
  def mfa_status_changed_disabled
    user = User.first
    SecurityMailer.mfa_status_changed(user, enabled: false)
  end
end
