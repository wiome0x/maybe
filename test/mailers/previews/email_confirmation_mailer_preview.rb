# Preview all emails at http://localhost:3000/rails/mailers/email_confirmation_mailer
class EmailConfirmationMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/email_confirmation_mailer/confirmation_email
  def confirmation_email
    user = User.find_by(unconfirmed_email: "new@example.com") || User.first
    EmailConfirmationMailer.with(user: user).confirmation_email
  end
end
