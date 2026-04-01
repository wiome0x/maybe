class ApplicationMailer < ActionMailer::Base
  default from: email_address_with_name(ENV.fetch("EMAIL_SENDER", "sender@maybe.local"), ENV.fetch("APP_NAME", "Maybe Finance"))
  layout "mailer"
end
