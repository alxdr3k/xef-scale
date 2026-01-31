import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "badge", "list"]
  static values = {
    transactionId: Number,
    workspaceId: Number,
    currentCategoryId: Number
  }

  connect() {
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener("click", this.boundCloseOnClickOutside)

    this.boundHandleCategoryCreated = this.handleCategoryCreated.bind(this)
    document.addEventListener("category:created", this.boundHandleCategoryCreated)
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside)
    document.removeEventListener("category:created", this.boundHandleCategoryCreated)
  }

  handleCategoryCreated(event) {
    if (!this.hasListTarget) return
    const { id, name, color } = event.detail

    // Skip if already exists
    if (this.listTarget.querySelector(`[data-category-id="${id}"]`)) return

    const btn = document.createElement("button")
    btn.type = "button"
    btn.dataset.action = "click->category-selector#selectCategory"
    btn.dataset.categoryId = id
    btn.className = "w-full text-left px-3 py-2 h-14 text-sm hover:bg-gray-50 flex items-center justify-between"

    const labelSpan = document.createElement("span")
    labelSpan.className = "flex items-center gap-2"
    const dot = document.createElement("span")
    dot.className = "w-3 h-3 rounded-full"
    dot.style.backgroundColor = color
    const nameText = document.createElement("span")
    nameText.textContent = name
    labelSpan.appendChild(dot)
    labelSpan.appendChild(nameText)
    btn.appendChild(labelSpan)

    // Insert in alphabetical order
    const existing = Array.from(this.listTarget.querySelectorAll("[data-category-id]"))
    const insertBefore = existing.find(el => {
      const text = el.textContent?.trim() || ""
      return text.localeCompare(name) > 0
    })

    if (insertBefore) {
      this.listTarget.insertBefore(btn, insertBefore)
    } else {
      // Insert before the "미분류로 설정" separator if it exists, otherwise append
      const hr = this.listTarget.querySelector("hr")
      if (hr) {
        this.listTarget.insertBefore(btn, hr)
      } else {
        this.listTarget.appendChild(btn)
      }
    }
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
