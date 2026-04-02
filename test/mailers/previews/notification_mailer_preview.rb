# Preview all emails at http://localhost:3000/rails/mailers/notification_mailer
class NotificationMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/notification_mailer/export_completed
  def export_completed
    family_export = FamilyExport.last || OpenStruct.new(
      family: Family.first,
      status: "completed",
      created_at: Time.current,
      filename: "maybe_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip"
    )

    NotificationMailer.export_completed(family_export)
  end

  # Preview this email at http://localhost:3000/rails/mailers/notification_mailer/sync_failure
  def sync_failure
    sync = Sync.where(status: :failed).last || OpenStruct.new(
      syncable: Account.first,
      error: "Connection timed out while fetching account data. Please try again later.",
      status: "failed"
    )

    NotificationMailer.sync_failure(sync)
  end
end
