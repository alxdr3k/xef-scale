import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "editor", "editInput"]

  edit() {
    this.displayTarget.classList.add("hidden")
    this.editorTarget.classList.remove("hidden")
    this.editInputTarget.focus()
    this.editInputTarget.selectionStart = this.editInputTarget.value.length
  }

  cancelEdit() {
    this.editorTarget.classList.add("hidden")
    this.displayTarget.classList.remove("hidden")
  }

  update(event) {
    event.preventDefault()
    const form = event.target.closest("form") || event.target
    const url = form.dataset.commentUrlValue
    const body = this.editInputTarget.value.trim()

    if (!body || !url) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ comment: { body } })
    })
    .then(response => {
      if (!response.ok) throw new Error("Update failed")
      this._reloadPanel()
    })
    .catch(() => {
      this.editInputTarget.classList.add("border-red-300")
      setTimeout(() => this.editInputTarget.classList.remove("border-red-300"), 1500)
    })
  }

  delete(event) {
    event.preventDefault()
    const button = event.currentTarget
    const url = button.dataset.commentUrlValue

    if (!url || !confirm("댓글을 삭제하시겠습니까?")) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(url, {
      method: "DELETE",
      headers: {
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      }
    })
    .then(response => {
      if (!response.ok) throw new Error("Delete failed")
      return response.text()
    })
    .then(html => {
      // Badge 카운트 업데이트
      try {
        if (html && html.includes("<turbo-stream")) {
          Turbo.renderStreamMessage(html)
        }
      } catch (e) {
        console.warn("Turbo stream badge update failed:", e)
      }
      this._reloadPanel()
    })
  }

  _reloadPanel() {
    const el = document.querySelector("[data-controller~='comment-panel']")
    if (!el) return
    const panelController = this.application.getControllerForElementAndIdentifier(el, "comment-panel")
    panelController?.commentAdded()
  }
}
