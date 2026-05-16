import { Controller } from "@hotwired/stimulus"

// ReviewTabsController — 검토함 인덱스의 세그먼트 탭 (ADR-0004).
//
// 클릭 시 data-tab 속성으로 패널 토글. shared/_segmented_tabs 추출은
// Phase 3 후속 PR (preflight §3.1, §3.2 Out of Scope에 명시되지 않았으나
// IA 골조 안에 인라인으로 두는 것이 본 PR 범위에서 자연스럽다).
export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    const tabName = event.currentTarget.dataset.tab

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tab === tabName
      tab.setAttribute("aria-selected", active ? "true" : "false")
      if (active) {
        tab.classList.add("border-action", "text-primary")
        tab.classList.remove("border-transparent", "text-secondary", "hover:text-primary")
      } else {
        tab.classList.remove("border-action", "text-primary")
        tab.classList.add("border-transparent", "text-secondary", "hover:text-primary")
      }
    })

    this.panelTargets.forEach((panel) => {
      if (panel.dataset.tab === tabName) {
        panel.removeAttribute("hidden")
      } else {
        panel.setAttribute("hidden", "")
      }
    })
  }
}
