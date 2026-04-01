import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "context", "commentsList", "commentsContainer", "emptyState"]

  _url = null
  _transactionId = null
  _rowId = null

  open(event) {
    const { transactionId, url, merchant, date, amount, rowId } = event.params

    // 이미 같은 거래가 열려있으면 닫기
    if (this._transactionId === transactionId) {
      this.close()
      return
    }

    // 이전 행 하이라이트 제거
    this._clearHighlight()

    this._url = url
    this._transactionId = transactionId
    this._rowId = rowId

    // 컨텍스트 표시
    this.contextTarget.textContent = `${merchant} · ${date} · ${amount}`

    // 댓글 로드
    this._loadComments()

    // 새 행 하이라이트
    const row = document.getElementById(rowId)
    if (row) row.classList.add("bg-indigo-50/50")

    // 패널 위치: 테이블 오른쪽 바로 옆, 행과 수직 정렬
    this._positionPanel(row)

    this.panelTarget.classList.remove("hidden")

    // 입력 포커스
    setTimeout(() => {
      const input = this.panelTarget.querySelector("[data-comment-form-target='input']")
      if (input) input.focus()
    }, 50)
  }

  close() {
    this._clearHighlight()
    this.panelTarget.classList.add("hidden")
    this._url = null
    this._transactionId = null
    this._rowId = null
  }

  get currentUrl() {
    return this._url
  }

  get currentTransactionId() {
    return this._transactionId
  }

  handleOutsideClick(event) {
    if (!this._url) return
    if (this.panelTarget.contains(event.target)) return
    if (event.target.closest("[data-comment-panel-trigger]")) return
    this.close()
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }

  commentAdded() {
    this._loadComments()
  }

  _positionPanel(row) {
    const panel = this.panelTarget
    if (!row) return

    const table = row.closest("table")
    const tableRect = table ? table.getBoundingClientRect() : row.getBoundingClientRect()
    const rowRect = row.getBoundingClientRect()
    const panelW = 384 // w-96
    const gap = 8

    // 수평: 테이블 오른쪽 끝 + gap
    let left = tableRect.right + gap
    // 화면 밖으로 나가면 테이블 왼쪽에 표시
    if (left + panelW > window.innerWidth - 8) {
      left = tableRect.left - panelW - gap
    }
    panel.style.left = `${Math.max(8, left)}px`
    panel.style.width = `${panelW}px`

    // 수직: 행 상단 기준
    const panelH = panel.offsetHeight || 400
    let top = rowRect.top
    top = Math.max(16, Math.min(top, window.innerHeight - panelH - 16))
    panel.style.top = `${top}px`
  }

  _loadComments() {
    if (!this._url) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this._url, {
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken
      }
    })
    .then(response => response.json())
    .then(data => {
      this.commentsContainerTarget.replaceChildren()
      const template = document.createElement("template")
      // Server-rendered HTML from our own controller
      template.innerHTML = data.html
      this.commentsContainerTarget.appendChild(template.content)
      this._updateEmptyState(data.count)
      // 스크롤 맨 아래로
      this.commentsListTarget.scrollTop = this.commentsListTarget.scrollHeight
    })
    .catch(() => {
      this.commentsContainerTarget.textContent = "댓글을 불러올 수 없습니다"
      this.commentsContainerTarget.className = "text-sm text-red-500 text-center py-4"
    })
  }

  _updateEmptyState(count) {
    if (count === 0) {
      this.emptyStateTarget.classList.remove("hidden")
      this.commentsContainerTarget.classList.add("hidden")
    } else {
      this.emptyStateTarget.classList.add("hidden")
      this.commentsContainerTarget.classList.remove("hidden")
    }
  }

  _clearHighlight() {
    if (this._rowId) {
      document.getElementById(this._rowId)?.classList.remove("bg-indigo-50/50")
    }
  }
}
