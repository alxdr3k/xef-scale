import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["day"]

  // Phase 5 contrast 감사 (Codex PR #207 P1): 옛 indigo class를 시맨틱
  // border-action/ring-action으로 토글. 템플릿 초기 selected class와 동기화
  // 되어야 두 셀이 동시 selected로 보이는 mismatch가 사라진다.
  select(event) {
    this.dayTargets.forEach(cell => {
      cell.classList.remove("border-action", "ring-1", "ring-action")
    })
    event.currentTarget.classList.add("border-action", "ring-1", "ring-action")
  }
}
