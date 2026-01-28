import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 3000 },
    enabled: { type: Boolean, default: false }
  }

  connect() {
    if (this.enabledValue) {
      this.startRefresh()
    }
  }

  disconnect() {
    this.stopRefresh()
  }

  startRefresh() {
    this.refreshTimer = setInterval(() => {
      // Turbo drive로 페이지 새로고침
      Turbo.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  stopRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
      this.refreshTimer = null
    }
  }

  enabledValueChanged() {
    if (this.enabledValue) {
      this.startRefresh()
    } else {
      this.stopRefresh()
    }
  }
}
