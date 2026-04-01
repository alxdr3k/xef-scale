import { Controller } from "@hotwired/stimulus"

// Dispatches a category:created event on document when connected, then removes itself.
// Used in turbo stream responses after category creation.
export default class extends Controller {
  static values = { id: Number, name: String, color: String }

  connect() {
    document.dispatchEvent(new CustomEvent("category:created", {
      detail: { id: this.idValue, name: this.nameValue, color: this.colorValue }
    }))
    this.element.remove()
  }
}
