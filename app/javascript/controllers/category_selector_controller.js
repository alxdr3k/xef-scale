import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "badge"]
  static values = {
    transactionId: Number,
    workspaceId: Number,
    currentCategoryId: Number
  }

  connect() {
    // Close dropdown when clicking outside
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener("click", this.boundCloseOnClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    if (this.dropdownTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.dropdownTarget.classList.remove("hidden")
  }

  close() {
    this.dropdownTarget.classList.add("hidden")
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  async selectCategory(event) {
    event.preventDefault()
    const categoryId = event.currentTarget.dataset.categoryId

    this.close()

    try {
      const response = await fetch(`/workspaces/${this.workspaceIdValue}/transactions/${this.transactionIdValue}/quick_update_category`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ category_id: categoryId || null })
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      console.error("Failed to update category:", error)
    }
  }

  openSlideover(event) {
    event.preventDefault()
    this.close()

    // Dispatch event to open slideover with category form
    const slideoverEvent = new CustomEvent("slideover:open", {
      detail: {
        url: `/workspaces/${this.workspaceIdValue}/categories/new?slideover=true&transaction_id=${this.transactionIdValue}`
      },
      bubbles: true
    })
    this.element.dispatchEvent(slideoverEvent)
  }
}
