import { Controller } from "@hotwired/stimulus"

// ReviewKeyboardController — Phase 5 검토함 키보드 단축키 (ADR-0008 / ui-redesign-plan §3.3).
//
// 검토함(reviews/show)에서 거래 행 사이 네비게이션:
//   j  — 다음 거래 행 focus
//   k  — 이전 거래 행 focus
//
// 텍스트 입력(input/textarea/contenteditable) 중에는 무시 — 사용자가 카테고리·
// 메모 등을 편집할 때 j/k가 글자 입력을 가로채면 안 된다.
//
// 추가 단축키(c=commit / d=discard / x=duplicate 해결 등)는 후속 슬라이스.
export default class extends Controller {
  static values = { rowSelector: { type: String, default: "tr[data-transaction-id]" } }

  handleKey(event) {
    // Modifier가 있으면 무시 (ctrl+j 등 다른 동작과 충돌 회피)
    if (event.metaKey || event.ctrlKey || event.altKey) return

    // 텍스트 입력 중이면 무시
    const target = event.target
    const tag = target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return
    if (target.isContentEditable) return

    if (event.key === "j") {
      event.preventDefault()
      this.focusRelative(1)
    } else if (event.key === "k") {
      event.preventDefault()
      this.focusRelative(-1)
    }
  }

  focusRelative(delta) {
    const rows = Array.from(this.element.querySelectorAll(this.rowSelectorValue))
    if (rows.length === 0) return

    const active = document.activeElement
    let idx = rows.indexOf(active.closest(this.rowSelectorValue))
    if (idx < 0) {
      // 현재 focus가 row가 아니면 가장 가까운(첫 또는 마지막) row
      idx = delta > 0 ? -1 : rows.length
    }
    const next = rows[Math.max(0, Math.min(rows.length - 1, idx + delta))]
    if (next) {
      next.focus({ preventScroll: false })
      next.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }
}
