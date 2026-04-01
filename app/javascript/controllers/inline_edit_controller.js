import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "editor", "input"]
  static values = { url: String, field: String, original: String }

  edit() {
    // Close any other open inline editors first
    document.querySelectorAll('[data-controller="inline-edit"]').forEach(el => {
      const controller = this.application.getControllerForElementAndIdentifier(el, "inline-edit")
      if (controller && controller !== this && controller.isEditing) {
        controller.save()
      }
    })

    this.displayTarget.style.display = "none"
    this.editorTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.inputTarget.select()
    this._editing = true

    // text/number input만 auto-size (date는 제외)
    const type = this.inputTarget.type
    if (type === "text" || type === "number") {
      const val = this.inputTarget.value
      const len = [...val].reduce((acc, c) => acc + (c.charCodeAt(0) > 127 ? 2 : 1), 0)
      this.inputTarget.size = Math.max(len + 1, 4)
      this.inputTarget.style.maxWidth = '100%'
    }
  }

  get isEditing() {
    return this._editing === true
  }

  save() {
    if (!this.isEditing) return Promise.resolve()

    const newValue = this.inputTarget.value
    if (newValue === this.originalValue) {
      this.cancel()
      return Promise.resolve()
    }

    this._editing = false
    this.inputTarget.disabled = true

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const rowId = this.element.closest('tr')?.id

    return fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ field: this.fieldValue, value: newValue })
    }).then(response => {
      if (response.ok) {
        return response.text()
      }
      throw new Error("Update failed")
    }).then(html => {
      Turbo.renderStreamMessage(html)
      // Add visual feedback to the newly replaced row
      if (rowId) {
        requestAnimationFrame(() => {
          const newRow = document.getElementById(rowId)
          if (newRow) {
            newRow.classList.add('inline-edit-success')
            setTimeout(() => {
              newRow.classList.remove('inline-edit-success')
            }, 600)
          }
        })
      }
    }).catch(() => {
      this.inputTarget.disabled = false
      this._showError()
      this.cancel()
    })
  }

  cancel() {
    this._editing = false
    this.inputTarget.value = this.originalValue
    this.inputTarget.disabled = false
    this.editorTarget.classList.add("hidden")
    this.displayTarget.style.display = ""
  }

  handleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      this.save()
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.cancel()
    } else if (event.key === "Tab") {
      event.preventDefault()
      const reverse = event.shiftKey
      this.save().then(() => {
        this._focusNextEditableCell(reverse)
      })
    }
  }

  handleBlur(event) {
    if (!this.isEditing) return

    // Delay to allow button clicks to register first
    requestAnimationFrame(() => {
      if (!this.isEditing) return
      // Check if focus moved to our action buttons
      if (this.element.contains(document.activeElement)) return
      this.save()
    })
  }

  _focusNextEditableCell(reverse = false) {
    const allEditors = Array.from(
      document.querySelectorAll('[data-controller="inline-edit"]')
    )
    const currentIndex = allEditors.indexOf(this.element)
    const nextIndex = reverse
      ? (currentIndex - 1 + allEditors.length) % allEditors.length
      : (currentIndex + 1) % allEditors.length
    const nextEditor = allEditors[nextIndex]
    if (nextEditor) {
      const controller = this.application.getControllerForElementAndIdentifier(nextEditor, "inline-edit")
      if (controller) {
        controller.edit()
      }
    }
  }

  _showError() {
    const row = this.element.closest('tr')
    if (!row) return
    row.classList.add('inline-edit-error')
    setTimeout(() => {
      row.classList.remove('inline-edit-error')
    }, 1000)
  }
}
