import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay"]
  static values = { page: String }

  connect() {
    const key = `onboarding_seen_${this.pageValue}`
    if (!localStorage.getItem(key)) {
      this.show()
      localStorage.setItem(key, "true")
    }
  }

  show() {
    this.overlayTargets.forEach(el => el.classList.remove("hidden"))
  }

  dismiss(event) {
    event?.preventDefault()
    this.overlayTargets.forEach(el => el.classList.add("hidden"))
  }

  reset() {
    const key = `onboarding_seen_${this.pageValue}`
    localStorage.removeItem(key)
    this.show()
  }
}
