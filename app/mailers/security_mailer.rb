class SecurityMailer < ApplicationMailer
  def new_device_login(user, session)
    @user = user
    @session = session
    @ip_address = session.ip_address
    @user_agent = session.user_agent
    @login_time = session.created_at

    mail to: @user.email, subject: t(".subject")
  end

  def password_changed(user)
    @user = user
    @changed_at = Time.current

    mail to: @user.email, subject: t(".subject")
  end

  def mfa_status_changed(user, enabled:)
    @user = user
    @enabled = enabled

    mail to: @user.email, subject: t(@enabled ? ".enabled_subject" : ".disabled_subject")
  end
end
