import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["categoryBar"]
  static values = {
    selectedId: { type: Number, default: 0 },
    year: Number,
    month: Number
  }

  selectCategory(event) {
    const categoryId = event.currentTarget.dataset.categoryId

    if (!categoryId) return

    // Update visual selection
    this.categoryBarTargets.forEach(bar => {
      bar.classList.remove("ring-2", "ring-offset-2", "ring-indigo-500")
    })
    event.currentTarget.classList.add("ring-2", "ring-offset-2", "ring-indigo-500")

    this.selectedIdValue = parseInt(categoryId)

    // Load category transactions via Turbo
    const url = `/dashboard/category_transactions/${categoryId}?year=${this.yearValue}&month=${this.monthValue}`
    fetch(url, {
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-Requested-With": "XMLHttpRequest"
      }
    })
    .then(response => response.text())
    .then(html => {
      Turbo.renderStreamMessage(html)
    })
  }

  clearSelection() {
    // Remove visual selection
    this.categoryBarTargets.forEach(bar => {
      bar.classList.remove("ring-2", "ring-offset-2", "ring-indigo-500")
    })
    this.selectedIdValue = 0

    // Reload page to show default recent transactions
    window.Turbo.visit(window.location.href, { action: "replace" })
  }
}
