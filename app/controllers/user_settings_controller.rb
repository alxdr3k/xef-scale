# frozen_string_literal: true

class UserSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
  end

  def update
    update_excluded_merchants
    update_theme

    if current_user.save
      respond_to do |format|
        format.html { redirect_to user_settings_path, notice: "설정이 저장되었습니다." }
        format.turbo_stream { flash.now[:notice] = "설정이 저장되었습니다." }
      end
    else
      redirect_to user_settings_path, alert: "설정 저장에 실패했습니다."
    end
  end

  private

  def update_excluded_merchants
    text = params.dig(:user, :excluded_merchants)
    current_user.set_excluded_merchants(text) unless text.nil?
  end

  # Phase 5: 테마 변경. User#theme= validates against `User::THEMES`.
  # `auto` / `light` / `dark` 외 값은 자동으로 `auto`로 정규화됨.
  def update_theme
    value = params.dig(:user, :theme)
    current_user.theme = value if value.present?
  end
end
