# frozen_string_literal: true

class UserSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    update_excluded_merchants

    if current_user.save
      redirect_to user_settings_path, notice: "설정이 저장되었습니다."
    else
      redirect_to user_settings_path, alert: "설정 저장에 실패했습니다."
    end
  end

  private

  def update_excluded_merchants
    text = params.dig(:user, :excluded_merchants)
    current_user.set_excluded_merchants(text) unless text.nil?
  end
end
