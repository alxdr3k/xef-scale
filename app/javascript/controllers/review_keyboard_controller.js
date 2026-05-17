import { Controller } from "@hotwired/stimulus"

// ReviewKeyboardController — Phase 5 검토함 키보드 단축키 (ADR-0008 / ui-redesign-plan §3.3).
//
// 검토함(reviews/show)에서:
//   j     — 다음 거래 행 focus
//   k     — 이전 거래 행 focus
//   c     — 현재 파싱 세션 commit (commitForm target)
//   d     — 현재 focused row를 이번 가져오기에서 *제외* (bulk_update delete)
//   Enter — 현재 focused row 선택 토글 (Phase 5 slice 7). bulk-select 컨트롤러
//           이 click 이벤트를 처리하므로 row.click()으로 dispatch.
//   ?     — 단축키 도움말 overlay 토글 (Shift+/)
//   Esc   — 도움말 overlay 열려 있으면 닫기
//
// 텍스트 입력 중에는 단축키 무시 (event.code/key 모두 layout-independent).
//
// 추가 단축키(x=duplicate)는 후속 슬라이스.
export default class extends Controller {
  static values = { rowSelector: { type: String, default: "tr[data-transaction-id]" } }
  static targets = ["commitForm", "excludeForm", "helpBackdrop", "helpDialog"]

  handleKey(event) {
    // 도움말 overlay가 열려 있으면 Esc/?/Tab만 처리, 다른 키는 background로 새지 않게 차단
    // (Codex PR #184 P2: modal 의미 보존 + ? 토글 + focus trap).
    if (this.helpOpen()) {
      if (event.key === "Escape") {
        event.preventDefault()
        this.hideHelp()
      } else if (event.key === "?" || (event.code === "Slash" && event.shiftKey)) {
        // Advertised 토글 behavior — ? 누르면 닫힘.
        event.preventDefault()
        this.hideHelp()
      } else if (event.key === "Tab") {
        // focus trap: dialog 안 focusable 사이만 순환.
        this.trapTab(event)
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
    } else if (event.code === "KeyD" || event.key === "d") {
      event.preventDefault()
      this.excludeCurrentRow()
    } else if (event.key === "Enter") {
      // Enter: 현재 row의 click을 dispatch → bulk-select 컨트롤러의 toggleRow 핸들러가
      // 자동으로 선택 토글. row가 부재하거나 deleted면 no-op.
      //
      // Codex PR #200 P1: row 자체에 focus 있을 때만 toggle. row 안 interactive
      // descendant(category 버튼, 관리 링크 등)에 focus 있을 때는 그 control의
      // native Enter 처리에 맡겨야 컨트롤 활성화가 보존된다.
      const active = document.activeElement
      const row = active?.closest(this.rowSelectorValue)
      if (row && active === row && row.dataset.deleted !== "true") {
        event.preventDefault()
        row.click()
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

  // Phase 5 slice 6: 현재 focused row를 이번 가져오기에서 제외.
  // 기존 bulk_update delete path 재사용 — transaction_excluded ImportReviewEvent
  // 기록 + reject_if_finalized 가드 자동 적용.
  //
  // 비활성 조건 (모두 no-op):
  //   - excludeForm target 부재 (read_only 또는 member_read — view에서 `unless @read_only`로
  //     이미 form 자체가 미렌더, write 권한 없는 member_read는 controller가 redirect)
  //   - 현재 focus가 row 안이 아님
  //   - row가 이미 deleted(rolled_back) — data-deleted="true"
  excludeCurrentRow() {
    if (!this.hasExcludeFormTarget) return

    const active = document.activeElement
    const row = active?.closest(this.rowSelectorValue)
    if (!row) return

    if (row.dataset.deleted === "true") return

    const id = row.dataset.transactionId
    if (!id) return

    // Lightweight guard — 실수로 d를 누른 사용자에게 한 번 더 확인.
    if (!window.confirm("이 거래를 이번 가져오기에서 제외하시겠습니까?")) return

    const form = this.excludeFormTarget
    const idsInput = form.querySelector("input[name='transaction_ids']")
    const actionInput = form.querySelector("input[name='bulk_action']")
    if (!idsInput || !actionInput) return

    idsInput.value = id
    actionInput.value = "delete"
    form.requestSubmit()
  }

  // Codex PR #184 P2: aria-modal focus trap.
  // Tab/Shift+Tab이 dialog 안 focusable 사이만 순환하도록.
  trapTab(event) {
    const focusables = this.helpDialogTarget.querySelectorAll(
      "button, [href], input, select, textarea, [tabindex]:not([tabindex='-1'])"
    )
    if (focusables.length === 0) {
      event.preventDefault()
      return
    }
    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    } else if (!this.helpDialogTarget.contains(document.activeElement)) {
      // 외부에서 dialog로 끌어와야 trap 의미 있음.
      event.preventDefault()
      first.focus()
    }
  }
}
