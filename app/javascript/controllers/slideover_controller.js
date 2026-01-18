import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop", "frame"]

  connect() {
    // Listen for custom events to open/close slideover
    this.boundOpen = this.openFromEvent.bind(this)
    this.boundClose = this.close.bind(this)
    this.boundTurboLoad = this.handleTurboLoad.bind(this)
    document.addEventListener("slideover:open", this.boundOpen)
    document.addEventListener("slideover:close", this.boundClose)

    // Listen for turbo frame load to auto-open
    if (this.hasFrameTarget) {
      this.frameTarget.addEventListener("turbo:frame-load", this.boundTurboLoad)
    }
  }

  disconnect() {
    document.removeEventListener("slideover:open", this.boundOpen)
    document.removeEventListener("slideover:close", this.boundClose)
    if (this.hasFrameTarget) {
      this.frameTarget.removeEventListener("turbo:frame-load", this.boundTurboLoad)
    }
  }

  openFromEvent(event) {
    if (event.detail && event.detail.url) {
      // Set the turbo frame src to load the content
      this.frameTarget.src = event.detail.url
    }
  }

  handleTurboLoad() {
    // Auto-open when content is loaded via Turbo
    this.open()
  }

  open() {
    this.panelTarget.classList.remove("translate-x-full")
    this.backdropTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
  }

  close() {
    this.panelTarget.classList.add("translate-x-full")
    this.backdropTarget.classList.add("hidden")
    document.body.style.overflow = ""
    // Clear the frame content
    this.frameTarget.src = ""
  }

  closeOnEsc(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  backdropClick(event) {
    if (event.target === this.backdropTarget) {
      this.close()
    }
  }
}
