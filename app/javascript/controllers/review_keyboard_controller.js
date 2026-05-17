import { Controller } from "@hotwired/stimulus"

// ReviewKeyboardController — Phase 5 검토함 키보드 단축키 (ADR-0008 / ui-redesign-plan §3.3).
//
// 검토함(reviews/show)에서:
//   j   — 다음 거래 행 focus
//   k   — 이전 거래 행 focus
//   c   — 현재 파싱 세션 commit (commitForm target)
//   ?   — 단축키 도움말 overlay 토글 (Shift+/)
//   Esc — 도움말 overlay 열려 있으면 닫기
//
// 텍스트 입력 중에는 단축키 무시 (event.code/key 모두 layout-independent).
//
// 추가 단축키(d=discard / x=duplicate / enter=select)는 후속 슬라이스.
export default class extends Controller {
  static values = { rowSelector: { type: String, default: "tr[data-transaction-id]" } }
  static targets = ["commitForm", "helpBackdrop", "helpDialog"]

  handleKey(event) {
    // 도움말 overlay가 열려 있으면 Esc만 처리, 다른 키는 background로 새지 않게 차단
    // (Codex PR #184 P2: modal 의미 보존).
    if (this.helpOpen()) {
      if (event.key === "Escape") {
        event.preventDefault()
        this.hideHelp()
      }
      return
    }

    // Modifier 가드 — ?(Shift+/)는 예외로 통과
    const isHelpToggle = event.key === "?" || (event.code === "Slash" && event.shiftKey)
    if ((event.metaKey || event.ctrlKey || event.altKey) && !isHelpToggle) return

    // 텍스트 입력 중이면 무시
    const target = event.target
    const tag = target.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return
    if (target.isContentEditable) return

    if (event.code === "KeyJ" || event.key === "j") {
      event.preventDefault()
      this.focusRelative(1)
    } else if (event.code === "KeyK" || event.key === "k") {
      event.preventDefault()
      this.focusRelative(-1)
    } else if (event.code === "KeyC" || event.key === "c") {
      if (this.hasCommitFormTarget) {
        event.preventDefault()
        this.commitFormTarget.requestSubmit()
      }
    } else if (isHelpToggle) {
      event.preventDefault()
      this.toggleHelp()
    }
  }

  focusRelative(delta) {
    const rows = Array.from(this.element.querySelectorAll(this.rowSelectorValue))
    if (rows.length === 0) return

    const active = document.activeElement
    let idx = rows.indexOf(active.closest(this.rowSelectorValue))
    if (idx < 0) {
      idx = delta > 0 ? -1 : rows.length
    }
    const next = rows[Math.max(0, Math.min(rows.length - 1, idx + delta))]
    if (next) {
      next.focus({ preventScroll: false })
      next.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  toggleHelp() {
    this.helpOpen() ? this.hideHelp() : this.showHelp()
  }

  showHelp(event) {
    event?.preventDefault()
    if (!this.hasHelpDialogTarget) return
    // Codex PR #184 P2: aria-modal a11y — 이전 focus 저장 후 dialog 안 첫
    // 인터랙티브 element(닫기 버튼)로 focus 이동.
    this.previousFocus = document.activeElement
    this.helpBackdropTarget.classList.remove("hidden")
    this.helpDialogTarget.classList.remove("hidden")
    const firstButton = this.helpDialogTarget.querySelector("button")
    if (firstButton) firstButton.focus()
  }

  hideHelp(event) {
    event?.preventDefault()
    if (!this.hasHelpDialogTarget) return
    this.helpBackdropTarget.classList.add("hidden")
    this.helpDialogTarget.classList.add("hidden")
    // 이전 focus 복원 — dialog 외부 컨텍스트로 자연스럽게 돌아가도록.
    if (this.previousFocus && typeof this.previousFocus.focus === "function") {
      this.previousFocus.focus()
    }
    this.previousFocus = null
  }

  helpOpen() {
    return this.hasHelpDialogTarget && !this.helpDialogTarget.classList.contains("hidden")
  }
}
