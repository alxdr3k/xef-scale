import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { debounceTimeout: { type: Number, default: 300 } }

  connect() {
    this.timeout = null
  }

  submitForm() {
    this.element.requestSubmit()
  }

  debounceSubmit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.submitForm()
    }, this.debounceTimeoutValue)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }
}
