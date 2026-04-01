import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "input", "submitButton"]

  connect() {
    this._updateSubmitButton()
  }

  autoResize() {
    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = Math.min(input.scrollHeight, 128) + "px"
    this._updateSubmitButton()
  }

  handleKeydown(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (this.inputTarget.value.trim()) {
        this.submit(event)
      }
    }
  }

  submit(event) {
    event.preventDefault()

    const body = this.inputTarget.value.trim()
    if (!body) return

    const panelController = this._getCommentPanelController()
    if (!panelController?.currentUrl) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    this.inputTarget.disabled = true
    this.submitButtonTarget.disabled = true

    fetch(panelController.currentUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ comment: { body } })
    })
    .then(response => {
      if (!response.ok) throw new Error("Failed")
      return response.text()
    })
    .then(html => {
      // Badge 카운트 업데이트 (turbo stream)
      try {
        if (html && html.includes("<turbo-stream")) {
          Turbo.renderStreamMessage(html)
        }
      } catch (e) {
        console.warn("Turbo stream badge update failed:", e)
      }

      // 폼 리셋
      this.inputTarget.value = ""
      this.inputTarget.style.height = "auto"
      this._updateSubmitButton()

      // 패널 댓글 목록 새로고침
      panelController.commentAdded()
    })
    .catch(() => {
      this.inputTarget.classList.add("border-red-300")
      setTimeout(() => this.inputTarget.classList.remove("border-red-300"), 1500)
    })
    .finally(() => {
      this.inputTarget.disabled = false
      this.submitButtonTarget.disabled = false
      this.inputTarget.focus()
    })
  }

  _getCommentPanelController() {
    // comment-panel 컨트롤러는 페이지 최상위 컨테이너에 선언됨
    const el = document.querySelector("[data-controller~='comment-panel']")
    if (!el) return null
    return this.application.getControllerForElementAndIdentifier(el, "comment-panel")
  }

  _updateSubmitButton() {
    const hasContent = this.inputTarget.value.trim().length > 0
    if (hasContent) {
      this.submitButtonTarget.classList.remove("hidden")
    } else {
      this.submitButtonTarget.classList.add("hidden")
    }
  }
}
