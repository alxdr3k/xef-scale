import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["merchant", "description", "category"]
  static values = { url: String }

  connect() {
    this.timeout = null
  }

  suggest() {
    clearTimeout(this.timeout)

    this.timeout = setTimeout(() => {
      this.fetchSuggestion()
    }, 300)
  }

  async fetchSuggestion() {
    const merchant = this.merchantTarget.value.trim()
    const description = this.descriptionTarget.value.trim()

    if (!merchant) return

    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set("merchant", merchant)
    if (description) url.searchParams.set("description", description)

    try {
      const response = await fetch(url, {
        headers: { "Accept": "application/json" }
      })

      if (response.ok) {
        const data = await response.json()
        if (data.category_id) {
          this.updateCategory(data.category_id)
        }
      }
    } catch (error) {
      console.error("Category suggestion failed:", error)
    }
  }

  updateCategory(categoryId) {
    const select = this.categoryTarget
    const currentValue = select.value

    if (currentValue !== String(categoryId)) {
      select.value = categoryId
      this.flashHighlight(select)
    }
  }

  flashHighlight(element) {
    // Remove any existing animation
    element.classList.remove("category-flash")

    // Force reflow to restart animation
    void element.offsetWidth

    // Add flash animation class
    element.classList.add("category-flash")

    // Remove after animation completes
    setTimeout(() => {
      element.classList.remove("category-flash")
    }, 800)
  }
}
