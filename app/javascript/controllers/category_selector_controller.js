import { Controller } from "@hotwired/stimulus"

// CategorySelectorController — 거래 row의 카테고리 드롭다운.
//
// Context-aware update URL: workspace ledger와 review session-scope 두 경로가
// 같은 partial을 공유한다. 과거에는 `/workspaces/:ws/transactions/:tx/quick_update_category`
// 를 hard-code해서 review 화면의 row도 workspace 라우트로 PATCH가 새 나갔다.
// 결과: `ReviewsController#reject_if_finalized` 가드를 우회하고, finalized 세션
// 에서도 카테고리 변경이 통과될 수 있었다.
//
// 이 컨트롤러는 이제 update URL과 request body shape을 explicit data value로
// 받는다:
//   data-category-selector-update-url-value  (필수)
//   data-category-selector-request-style-value
//     "id"    → POST body { category_id: id }    (workspace#quick_update_category)
//     "field" → POST body { field: "category_id", value: id } (reviews#update_transaction)
//
// 새 카테고리 슬라이드오버 URL도 review context를 보존해야 하므로 parsing_session_id
// 가 있으면 query string에 함께 실어 보낸다.
export default class extends Controller {
  static targets = ["dropdown", "badge", "list"]
  static values = {
    transactionId: Number,
    workspaceId: Number,
    currentCategoryId: Number,
    updateUrl: String,
    requestStyle: { type: String, default: "id" },
    parsingSessionId: { type: String, default: "" }
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
    this.adjustDropdownPosition()
  }

  adjustDropdownPosition() {
    const dropdown = this.dropdownTarget
    const rect = dropdown.getBoundingClientRect()
    const viewportHeight = window.innerHeight

    if (rect.bottom > viewportHeight) {
      dropdown.style.top = "auto"
      dropdown.style.bottom = "100%"
      dropdown.style.marginTop = ""
      dropdown.style.marginBottom = "4px"
    } else {
      dropdown.style.top = ""
      dropdown.style.bottom = ""
      dropdown.style.marginTop = ""
      dropdown.style.marginBottom = ""
    }
  }

  close() {
    const dropdown = this.dropdownTarget
    dropdown.classList.add("hidden")
    dropdown.style.top = ""
    dropdown.style.bottom = ""
    dropdown.style.marginTop = ""
    dropdown.style.marginBottom = ""
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

    const url = this.updateUrlValue ||
      `/workspaces/${this.workspaceIdValue}/transactions/${this.transactionIdValue}/quick_update_category`

    const body = this.requestStyleValue === "field"
      ? { field: "category_id", value: categoryId || "" }
      : { category_id: categoryId || null }

    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify(body)
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

    const params = new URLSearchParams({
      slideover: "true",
      transaction_id: String(this.transactionIdValue)
    })
    if (this.parsingSessionIdValue) {
      // Review context: slideover create must re-render the row with session-scoped
      // URLs so subsequent edits keep hitting ReviewsController guards.
      params.set("parsing_session_id", this.parsingSessionIdValue)
    }

    const slideoverEvent = new CustomEvent("slideover:open", {
      detail: {
        url: `/workspaces/${this.workspaceIdValue}/categories/new?${params.toString()}`
      },
      bubbles: true
    })
    this.element.dispatchEvent(slideoverEvent)
  }
}
