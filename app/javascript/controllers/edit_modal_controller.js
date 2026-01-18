import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content"]
  static values = {
    url: String,
    transactionId: Number,
    allowance: Boolean
  }

  async open() {
    // Show modal
    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"

    // Fetch edit form
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "text/html",
          "X-Requested-With": "XMLHttpRequest"
        }
      })

      if (!response.ok) throw new Error("Failed to load form")

      const html = await response.text()

      // Extract form from the response
      const parser = new DOMParser()
      const doc = parser.parseFromString(html, "text/html")
      const form = doc.querySelector("form")

      if (form) {
        // Modify form to use turbo_stream and add allowance checkbox
        form.setAttribute("data-turbo", "true")
        form.setAttribute("data-action", "turbo:submit-end->edit-modal#handleSubmit")

        // Add allowance checkbox before submit buttons
        const submitDiv = form.querySelector(".flex.justify-end")
        if (submitDiv) {
          const allowanceDiv = document.createElement("div")
          allowanceDiv.className = "mb-4 flex items-center"

          const checkbox = document.createElement("input")
          checkbox.type = "checkbox"
          checkbox.name = "allowance"
          checkbox.id = "allowance"
          checkbox.value = "1"
          checkbox.checked = this.allowanceValue
          checkbox.className = "h-4 w-4 text-indigo-600 focus:ring-indigo-500 border-gray-300 rounded"

          const label = document.createElement("label")
          label.htmlFor = "allowance"
          label.className = "ml-2 block text-sm text-gray-900"
          label.textContent = "💰 용돈으로 표시"

          allowanceDiv.appendChild(checkbox)
          allowanceDiv.appendChild(label)
          submitDiv.parentNode.insertBefore(allowanceDiv, submitDiv)
        }

        this.contentTarget.textContent = ""
        this.contentTarget.appendChild(form)
      }
    } catch (error) {
      console.error("Error loading form:", error)
      const errorDiv = document.createElement("div")
      errorDiv.className = "text-red-600 text-center py-4"
      errorDiv.textContent = "폼을 불러오는데 실패했습니다."
      this.contentTarget.textContent = ""
      this.contentTarget.appendChild(errorDiv)
    }
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""
    const loadingDiv = document.createElement("div")
    loadingDiv.className = "text-center py-8 text-gray-500"
    loadingDiv.textContent = "로딩 중..."
    this.contentTarget.textContent = ""
    this.contentTarget.appendChild(loadingDiv)
  }

  handleSubmit(event) {
    if (event.detail.success) {
      this.close()
    }
  }

  // Close modal when clicking outside
  clickOutside(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  // Close on escape key
  handleKeyup(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }

  connect() {
    this.boundHandleKeyup = this.handleKeyup.bind(this)
    document.addEventListener("keyup", this.boundHandleKeyup)
  }

  disconnect() {
    document.removeEventListener("keyup", this.boundHandleKeyup)
    document.body.style.overflow = ""
  }
}
