class AddExtraRecipientsToWeeklyReportSubscriptions < ActiveRecord::Migration[7.2]
  def change
    add_column :weekly_report_subscriptions, :extra_recipient_emails, :string, array: true, default: []
  end
end
