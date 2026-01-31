# frozen_string_literal: true

class UserSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    update_statement_password
    update_excluded_merchants
    update_exclude_card_withdrawals

    if current_user.save
      redirect_to user_settings_path, notice: "설정이 저장되었습니다."
    else
      redirect_to user_settings_path, alert: "설정 저장에 실패했습니다."
    end
  end

  private

  def update_statement_password
    password = params.dig(:user, :statement_password)
    current_user.set_statement_password(password) if password.present?
  end

  def update_excluded_merchants
    text = params.dig(:user, :excluded_merchants)
    current_user.set_excluded_merchants(text) unless text.nil?
  end

  def update_exclude_card_withdrawals
    value = params.dig(:user, :exclude_card_withdrawals)
    current_user.set_exclude_card_withdrawals(value) unless value.nil?
  end
end
