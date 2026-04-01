class MfaController < ApplicationController
  layout :determine_layout
  skip_authentication only: [ :verify, :verify_code ]

  MFA_SESSION_TTL = 5.minutes

  def new
    redirect_to root_path if Current.user.otp_required?
    Current.user.setup_mfa! unless Current.user.otp_secret.present?
  end

  def create
    if Current.user.verify_otp?(params[:code])
      @backup_codes = Current.user.enable_mfa!
      render :backup_codes
    else
      Current.user.disable_mfa!
      redirect_to new_mfa_path, alert: t(".invalid_code")
    end
  end

  def verify
    @user = find_mfa_user

    if @user.nil?
      session.delete(:mfa_user_id)
      session.delete(:mfa_user_id_at)
      redirect_to new_session_path
    end
  end

  def verify_code
    @user = find_mfa_user

    if @user.nil?
      session.delete(:mfa_user_id)
      session.delete(:mfa_user_id_at)
      redirect_to new_session_path, alert: t(".session_expired")
      return
    end

    if @user.mfa_locked?
      flash.now[:alert] = t(".account_locked")
      render :verify, status: :unprocessable_entity
      return
    end

    if @user.verify_otp?(params[:code])
      session.delete(:mfa_user_id)
      session.delete(:mfa_user_id_at)
      @session = create_session_for(@user)
      redirect_to root_path
    else
      flash.now[:alert] = @user.mfa_locked? ? t(".account_locked") : t(".invalid_code")
      render :verify, status: :unprocessable_entity
    end
  end

  def disable
    unless Current.user.authenticate(params[:password])
      redirect_to settings_security_path, alert: t(".invalid_password")
      return
    end

    Current.user.disable_mfa!
    redirect_to settings_security_path, notice: t(".success")
  end

  private

    def determine_layout
      if action_name.in?(%w[verify verify_code])
        "auth"
      else
        "settings"
      end
    end

    def find_mfa_user
      user_id = session[:mfa_user_id]
      created_at = session[:mfa_user_id_at]

      return nil if user_id.blank?
      return nil if created_at.blank? || Time.parse(created_at) < MFA_SESSION_TTL.ago

      User.find_by(id: user_id)
    end
end
