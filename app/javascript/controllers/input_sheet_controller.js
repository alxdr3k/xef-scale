import { Controller } from "@hotwired/stimulus"

// InputSheetController — 3-way 입력 시트 (ADR-0004, Phase 3.3).
//
// 검토함 / 입력 기록 페이지에서 "+ 새로 가져오기" 버튼이 시트를 연다.
// 데스크탑은 중앙 modal, 모바일은 bottom sheet.
//
// 시트는 role="dialog" aria-modal="true"를 선언하므로 다음 a11y 계약을 만족해야 한다
// (Codex hotfix C):
//   - open 시 focus를 sheet 안 첫 focusable 요소로 이동
//   - Tab/Shift+Tab은 sheet 안에서 cycle (focus trap)
//   - Escape로 close
//   - close 후 focus를 trigger(또는 이전 활성 요소)로 복원
//   - turbo:before-cache에서 stale open 상태를 정리해 캐시된 스냅샷이 깨끗하도록
//
// 사용자가 backdrop을 클릭하거나 close 버튼을 누를 때도 위 복원이 동작해야 한다.
const FOCUSABLE_SELECTOR = [
  "a[href]",
  "area[href]",
  "input:not([disabled]):not([type='hidden'])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "button:not([disabled])",
  "iframe",
  "object",
  "embed",
  "[tabindex]:not([tabindex='-1'])",
  "[contenteditable=true]"
].join(",")

export default class extends Controller {
  static targets = ["backdrop", "sheet", "trigger"]

  initialize() {
    this.resetBeforeCache = this.resetBeforeCache.bind(this)
  }

  connect() {
    document.addEventListener("turbo:before-cache", this.resetBeforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.resetBeforeCache)
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    event?.preventDefault()
    // 복원 대상: open을 트리거한 요소(보통 trigger 버튼). 없으면 첫 trigger.
    this.previousActiveElement = document.activeElement
    this.backdropTarget.classList.remove("hidden")
    this.sheetTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")

    // Focus를 sheet 안 첫 focusable로 이동. 다음 프레임으로 미루면 transition/
    // display 변경 후 layout이 안정된 상태에서 focus가 적용된다.
    requestAnimationFrame(() => {
      const first = this.firstFocusable()
      first?.focus()
    })
  }

  close(event) {
    event?.preventDefault()
    const wasOpen = !this.sheetTarget.classList.contains("hidden")
    this.backdropTarget.classList.add("hidden")
    this.sheetTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")

    if (wasOpen) {
      const restore = this.previousActiveElement
      this.previousActiveElement = null
      if (restore && document.contains(restore) && typeof restore.focus === "function") {
        restore.focus()
      } else if (this.hasTriggerTarget) {
        this.triggerTarget.focus()
      }
    }
  }

  handleKeydown(event) {
    if (this.sheetTarget.classList.contains("hidden")) return

    if (event.key === "Escape") {
      this.close(event)
      return
    }

    if (event.key === "Tab") {
      this.trapTab(event)
    }
  }

  // Tab/Shift+Tab이 sheet 바깥으로 새지 않도록 wrap-around.
  trapTab(event) {
    const focusables = this.focusableElements()
    if (focusables.length === 0) {
      event.preventDefault()
      return
    }

    const first = focusables[0]
    const last = focusables[focusables.length - 1]
    const active = document.activeElement

    if (event.shiftKey) {
      if (active === first || !this.sheetTarget.contains(active)) {
        event.preventDefault()
        last.focus()
      }
    } else {
      if (active === last || !this.sheetTarget.contains(active)) {
        event.preventDefault()
        first.focus()
      }
    }
  }

  focusableElements() {
    return Array.from(this.sheetTarget.querySelectorAll(FOCUSABLE_SELECTOR))
                .filter(el => !el.hasAttribute("disabled") && el.offsetParent !== null)
  }

  firstFocusable() {
    const focusables = this.focusableElements()
    // close 버튼은 focusable에 포함되지만 첫 focus 대상으로는 본문 안의 첫 input/
    // textarea가 더 자연스럽다. 단순화를 위해 그냥 첫 focusable 사용.
    return focusables[0]
  }

  resetBeforeCache() {
    // 캐시되는 스냅샷에는 닫힌 상태가 저장돼야 한다 (DOM 클래스 직접 조작).
    // close()는 focus restore까지 수행하므로 캐시 정리에는 클래스만 정리.
    this.backdropTarget?.classList.add("hidden")
    this.sheetTarget?.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
    this.previousActiveElement = null
  }
}
