import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const selectedTab = event.params.tab

    this.tabTargets.forEach(tab => {
      const isActive = tab.dataset.inputTabsTabParam === selectedTab
      tab.classList.toggle("border-indigo-500", isActive)
      tab.classList.toggle("text-indigo-600", isActive)
      tab.classList.toggle("border-transparent", !isActive)
      tab.classList.toggle("text-gray-500", !isActive)
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== selectedTab)
    })
  }
}
