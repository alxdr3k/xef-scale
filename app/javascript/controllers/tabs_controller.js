import { Controller } from "@hotwired/stimulus"

// Phase 5 cleanup (Scope C-2): tab active/inactive class를 ADR-0008 semantic
// 토큰으로 상수화. 가이드 (PR #217 P2 / #218 P1):
//   - actionable nav (active) → text-action + border-action
//   - actionable nav (inactive) → text-secondary, hover:text-primary
const ACTIVE_TAB_CLASSES = ["text-action", "border-action"]
const INACTIVE_TAB_CLASSES = ["text-secondary", "hover:text-primary", "border-transparent"]

export default class extends Controller {
  static targets = ["tab", "panel"]

  connect() {
    this.showTab(0)
  }

  switch(event) {
    event.preventDefault()
    const tab = event.currentTarget
    const index = this.tabTargets.indexOf(tab)
    this.showTab(index)
  }

  showTab(index) {
    // Update tab styles
    this.tabTargets.forEach((tab, i) => {
      if (i === index) {
        tab.classList.remove(...INACTIVE_TAB_CLASSES)
        tab.classList.add(...ACTIVE_TAB_CLASSES)
        tab.setAttribute('aria-selected', 'true')
      } else {
        tab.classList.remove(...ACTIVE_TAB_CLASSES)
        tab.classList.add(...INACTIVE_TAB_CLASSES)
        tab.setAttribute('aria-selected', 'false')
      }
    })

    // Show/hide panels
    this.panelTargets.forEach((panel, i) => {
      if (i === index) {
        panel.classList.remove('hidden')
      } else {
        panel.classList.add('hidden')
      }
    })
  }
}
