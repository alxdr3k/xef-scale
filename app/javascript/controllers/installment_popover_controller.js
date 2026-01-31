import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "popover", "monthInput", "totalInput"]
  static values = {
    url: String,
    paymentType: String,
    installmentMonth: { type: Number, default: 1 },
    installmentTotal: { type: Number, default: 2 }
  }

  handleChange(event) {
    if (event.target.value === "installment") {
      this.showPopover()
    } else {
      // Non-installment: auto-submit
      event.target.blur()
      this.element.requestSubmit()
    }
  }

  showPopover() {
    this.monthInputTarget.value = this.installmentMonthValue
    this.totalInputTarget.value = this.installmentTotalValue
    this.popoverTarget.classList.remove("hidden")
    this.monthInputTarget.focus()
    this.monthInputTarget.select()
  }

  confirm(event) {
    event.preventDefault()
    const month = parseInt(this.monthInputTarget.value, 10)
    const total = parseInt(this.totalInputTarget.value, 10)

    if (!month || month < 1 || !total || total < 2) return

    this.popoverTarget.classList.add("hidden")

    // Build form data and submit via fetch for multi-field update
    const formData = new FormData()
    formData.append("transaction[payment_type]", "installment")
    formData.append("transaction[installment_month]", month)
    formData.append("transaction[installment_total]", total)

    const token = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": token,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: formData
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
    }).then(html => {
      if (html) {
        Turbo.renderStreamMessage(html)
      }
    })
  }

  cancel(event) {
    event.preventDefault()
    this.popoverTarget.classList.add("hidden")
    this.selectTarget.value = this.paymentTypeValue
  }

  handleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.confirm(event)
    } else if (event.key === "Escape") {
      this.cancel(event)
    }
  }

  // Close popover on outside click
  clickOutside(event) {
    if (!this.popoverTarget.classList.contains("hidden") &&
        !this.popoverTarget.contains(event.target) &&
        !this.selectTarget.contains(event.target)) {
      this.cancel(event)
    }
  }

  connect() {
    this._clickOutsideHandler = this.clickOutside.bind(this)
    document.addEventListener("click", this._clickOutsideHandler)
  }

  disconnect() {
    document.removeEventListener("click", this._clickOutsideHandler)
  }
}
