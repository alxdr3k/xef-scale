import { Controller } from "@hotwired/stimulus"

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
        tab.classList.remove('text-gray-500', 'hover:text-gray-700', 'border-transparent')
        tab.classList.add('text-indigo-600', 'border-indigo-600')
        tab.setAttribute('aria-selected', 'true')
      } else {
        tab.classList.remove('text-indigo-600', 'border-indigo-600')
        tab.classList.add('text-gray-500', 'hover:text-gray-700', 'border-transparent')
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
