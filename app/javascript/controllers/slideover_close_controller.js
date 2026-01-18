import { Controller } from "@hotwired/stimulus"

// This controller is used to close the slideover when mounted via turbo stream
export default class extends Controller {
  connect() {
    // Dispatch event to close the slideover
    document.dispatchEvent(new CustomEvent("slideover:close"))
    // Remove this element after triggering
    this.element.remove()
  }
}
