class WeeklyReportMailer < ApplicationMailer
  helper :application

  def weekly_report
    @weekly_report = params[:weekly_report]
    @report_presenter = WeeklyReportPresenter.new(@weekly_report)
    @period = @weekly_report.period

    I18n.with_locale(@weekly_report.user.family.locale) do
      mail(
        to: @weekly_report.recipient_email,
        subject: I18n.t(
          "weekly_report_mailer.weekly_report.subject",
          end_date: I18n.l(@period.end_date, format: :long)
        )
      )
    end
  end
end
