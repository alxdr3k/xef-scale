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
        format.turbo_stream do
          flash.now[:notice] = "설정이 저장되었습니다."
          # ADR-0011 §Decision 3 X — Codex PR #180 P1: turbo_stream 응답은
          # render 또는 redirect를 명시해야 한다 (implicit template render는
          # 존재하지 않는 update.turbo_stream.erb를 찾아 MissingTemplate 발생).
          render turbo_stream: turbo_stream.update("flash", partial: "shared/flash")
        end
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
