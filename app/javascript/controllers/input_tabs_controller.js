import { Controller } from "@hotwired/stimulus"

// Phase 5 cleanup (Scope C-2): tabs_controller와 같은 의미 토큰 사용.
export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const selectedTab = event.params.tab

    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.inputTabsTabParam === selectedTab
      tab.classList.toggle("border-action", isActive)
      tab.classList.toggle("text-action", isActive)
      tab.classList.toggle("border-transparent", !isActive)
      tab.classList.toggle("text-secondary", !isActive)
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== selectedTab)
    })
  }
}
