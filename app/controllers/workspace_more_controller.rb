# Phase 3.5 (ADR-0004 / ui-redesign-plan §3.5) — 더보기 탭의 전용 페이지.
# 그룹 리스트 카드(워크스페이스 / AI 설정 / 내 계정 / 도구 / 위험한 작업)의
# 진입점만 모은다. 각 그룹의 세부 화면은 기존 컨트롤러 그대로 사용한다
# (workspaces#settings, allowances#index, user_settings#show 등) — 라우트
# 호환 유지.
#
# 권한: 워크스페이스 read만 요구한다. 위험한 작업(워크스페이스 삭제 등)은
# 클릭 후 destination 컨트롤러에서 자체 admin 권한 게이트가 적용됨.
class WorkspaceMoreController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :require_workspace_access

  def show
    @membership = current_user.workspace_memberships.find_by(workspace_id: @workspace.id)
  end
end
