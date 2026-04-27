class WeeklyReportDispatchJob < ApplicationJob
  queue_as :scheduled

  def perform(reference_time: Time.current)
    track_run("dispatch_weekly_reports") do
      WeeklyReportSubscription.enabled.includes(:user).find_each do |subscription|
        next unless subscription.due_for_dispatch?(reference_time: reference_time)

        dispatch_for(subscription, reference_time: reference_time)
      end
    end
  end

  private
    def dispatch_for(subscription, reference_time:)
      user = subscription.user
      period = subscription.period_for(reference_time: reference_time)
      scheduled_for = subscription.scheduled_for(reference_time: reference_time)

      return if user.weekly_reports.exists?(period_start_date: period.start_date, period_end_date: period.end_date)

      weekly_report = user.weekly_reports.new(
        period_start_date: period.start_date,
        period_end_date: period.end_date,
        scheduled_for: scheduled_for
      )

      if user.email.blank? || !user.active?
        weekly_report.status = :skipped
        weekly_report.error_message = user.email.blank? ? "Recipient email is missing" : "User is inactive"
        weekly_report.payload = {
          recipient_email: user.email,
          period: {
            key: period.key,
            start_date: period.start_date.iso8601,
            end_date: period.end_date.iso8601
          }
        }
        weekly_report.save!
        return
      end

      weekly_report.status = :pending
      weekly_report.payload = WeeklyReportBuilder.new(user: user, period: period, extra_recipient_emails: subscription.extra_recipient_emails).build
      weekly_report.save!

      message = WeeklyReportMailer.with(weekly_report: weekly_report).weekly_report
      weekly_report.update!(
        html_body: message.html_part&.body&.to_s || message.body.encoded,
        text_body: message.text_part&.body&.to_s || message.body.encoded
      )

      message.deliver_now
      weekly_report.update!(status: :sent, sent_at: Time.current)
      enqueue_bark_notification(user, weekly_report)
    rescue => error
      weekly_report&.update(status: :failed, error_message: error.message.truncate(500))
      Rails.logger.error("Weekly report dispatch failed for user #{user&.id}: #{error.class}: #{error.message}")
    end

    def enqueue_bark_notification(user, weekly_report)
      report_path = Rails.application.routes.url_helpers.settings_weekly_report_delivery_path(weekly_report)

      BarkNotificationScheduler.enqueue!(
        user: user,
        category: "weekly_report",
        title: "Weekly report ready",
        body: "#{weekly_report.period_start_date} - #{weekly_report.period_end_date}",
        target_url: AppUrlBuilder.url_for(report_path),
        source_key: "weekly_report:#{weekly_report.id}",
        occurred_at: weekly_report.sent_at || Time.current,
        payload: {
          weekly_report_id: weekly_report.id,
          period_start_date: weekly_report.period_start_date.iso8601,
          period_end_date: weekly_report.period_end_date.iso8601
        }
      )
    end
end
