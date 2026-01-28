import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit(event) {
    // Blur the triggering element to prevent focus jumping after turbo_stream replace
    event?.target?.blur()
    this.element.requestSubmit()
  }
}
