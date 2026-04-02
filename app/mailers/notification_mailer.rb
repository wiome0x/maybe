class NotificationMailer < ApplicationMailer
  def export_completed(family_export)
    @family_export = family_export
    @user = family_export.family.users.find_by(role: :admin) || family_export.family.users.first

    mail to: @user.email, subject: t(".subject")
  end

  def sync_failure(sync)
    @sync = sync
    @account_name = sync.syncable.is_a?(Account) ? sync.syncable.name : sync.syncable_type
    @error_message = sync.error
    @user = sync.syncable.is_a?(Family) ? sync.syncable.users.find_by(role: :admin) : sync.syncable.family.users.find_by(role: :admin)

    return unless @user

    mail to: @user.email, subject: t(".subject", account: @account_name)
  end
end
