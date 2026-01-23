import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "bulkActions", "cardList", "card", "toggleButton", "toggleIcon"]

  connect() {
    this.collapsed = false
  }

  toggleCollapse() {
    this.collapsed = !this.collapsed

    if (this.hasCardListTarget) {
      if (this.collapsed) {
        this.cardListTarget.classList.add("hidden")
      } else {
        this.cardListTarget.classList.remove("hidden")
      }
    }

    if (this.hasToggleIconTarget) {
      if (this.collapsed) {
        this.toggleIconTarget.classList.add("rotate-180")
      } else {
        this.toggleIconTarget.classList.remove("rotate-180")
      }
    }
  }

  updateCount(count) {
    if (this.hasCountTarget) {
      this.countTarget.textContent = count
    }
  }
}
