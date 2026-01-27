# frozen_string_literal: true

class UserSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    if update_statement_passwords
      redirect_to user_settings_path, notice: "설정이 저장되었습니다."
    else
      redirect_to user_settings_path, alert: "설정 저장에 실패했습니다."
    end
  end

  private

  def update_statement_passwords
    password_params = params.dig(:user, :statement_passwords) || {}

    User::INSTITUTIONS_WITH_PASSWORD.each_key do |key|
      password = password_params[key]
      # 값이 있을 때만 업데이트 (빈 칸은 기존 값 유지)
      current_user.set_statement_password(key, password) if password.present?
    end

    current_user.save
  end
end
