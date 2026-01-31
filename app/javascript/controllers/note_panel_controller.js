import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "input", "context", "saveButton"]

  // 현재 열린 상태 정보
  _url = null
  _original = null
  _rowId = null

  open(event) {
    const { url, original, merchant, date, amount, rowId } = event.params

    // 이미 열려있고 변경사항 있으면 자동 저장 후 전환
    if (this._url && this._isDirty()) {
      this._saveQuietly()
        .catch(() => {})
        .then(() => {
          this._show(url, original, merchant, date, amount, rowId)
        })
      return
    }

    this._show(url, original, merchant, date, amount, rowId)
  }

  _show(url, original, merchant, date, amount, rowId) {
    // 이전 행 하이라이트 제거 (rowId 덮어쓰기 전에)
    this._clearHighlight()

    this._url = url
    this._original = original || ""
    this._rowId = rowId

    // 컨텍스트 표시
    this.contextTarget.textContent = `${merchant} · ${date} · ${amount}`
    this.inputTarget.value = this._original

    // 새 행 하이라이트
    const row = document.getElementById(rowId)
    if (row) row.classList.add("bg-indigo-50/50")

    // 패널 위치: 테이블 오른쪽 바로 옆, 행과 수직 정렬
    const panel = this.panelTarget
    if (row) {
      const table = row.closest('table')
      const tableRect = table ? table.getBoundingClientRect() : row.getBoundingClientRect()
      const rowRect = row.getBoundingClientRect()
      const panelW = 320 // w-80
      const gap = 8

      // 수평: 테이블 왼쪽 바로 옆
      let left = tableRect.left - panelW - gap
      // 화면 밖으로 나가면 테이블 오른쪽에 표시
      if (left < 8) {
        left = tableRect.right + gap
      }
      panel.style.left = `${Math.max(8, left)}px`

      // 수직: 행 중앙 기준
      const panelH = panel.offsetHeight || 300
      let top = rowRect.top + rowRect.height / 2 - panelH / 2
      top = Math.max(16, Math.min(top, window.innerHeight - panelH - 16))
      panel.style.top = `${top}px`
    }

    panel.classList.remove("hidden")
    this.inputTarget.focus()
  }

  save() {
    const newValue = this.inputTarget.value
    if (newValue === this._original) {
      this.close()
      return
    }

    this._saveQuietly().then(() => this.close())
  }

  _saveQuietly() {
    const newValue = this.inputTarget.value
    if (newValue === this._original) return Promise.resolve()

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const rowId = this._rowId

    return fetch(this._url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "Accept": "text/vnd.turbo-stream.html",
        "X-CSRF-Token": csrfToken
      },
      body: JSON.stringify({ field: "notes", value: newValue })
    }).then(response => {
      if (!response.ok) throw new Error("Update failed")
      return response.text()
    }).then(html => {
      Turbo.renderStreamMessage(html)
      // 저장 후 행 하이라이트 피드백
      if (rowId) {
        requestAnimationFrame(() => {
          const newRow = document.getElementById(rowId)
          if (newRow) {
            newRow.classList.add('inline-edit-success')
            setTimeout(() => newRow.classList.remove('inline-edit-success'), 600)
          }
        })
      }
    }).catch(() => {
      // 에러 시 행에 에러 피드백
      if (rowId) {
        const row = document.getElementById(rowId)
        if (row) {
          row.classList.add('inline-edit-error')
          setTimeout(() => row.classList.remove('inline-edit-error'), 1000)
        }
      }
    })
  }

  close() {
    this._clearHighlight()
    this.panelTarget.classList.add("hidden")
    this._url = null
    this._original = null
    this._rowId = null
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      event.preventDefault()
      this.save()
    }
  }

  handleOutsideClick(event) {
    if (!this._url) return
    if (this.panelTarget.contains(event.target)) return
    if (event.target.closest("[data-note-panel-trigger]")) return
    if (this._isDirty()) {
      this.save()
    } else {
      this.close()
    }
  }

  _isDirty() {
    return this.inputTarget.value !== this._original
  }

  _clearHighlight() {
    if (this._rowId) {
      document.getElementById(this._rowId)?.classList.remove("bg-indigo-50/50")
    }
  }
}
