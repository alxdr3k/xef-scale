import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "content", "loading", "empty", "summary", "counter", "progress", "undoBtn", "footer"]
  static values = { url: String }

  connect() {
    this.pairs = []
    this.currentIndex = 0
    this.deletedIds = new Set()
    this.lastAction = null
    this.stats = { deleted: 0, kept: 0, skipped: 0 }
    this.editingField = null
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.showLoading()
    this.fetchDuplicates()
    document.addEventListener("keydown", this.handleKeydown)
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.removeEventListener("keydown", this.handleKeydown)

    if (this.deletedIds.size > 0 || this.hasEdited) {
      window.location.reload()
    }
  }

  async fetchDuplicates() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) throw new Error("Failed to fetch duplicates")

      const data = await response.json()
      this.pairs = data.pairs || []

      if (this.pairs.length === 0) {
        this.showEmpty()
      } else {
        this.currentIndex = 0
        this.renderPair()
      }
    } catch (error) {
      console.error("Error fetching duplicates:", error)
      this.showEmpty()
    }
  }

  showLoading() {
    this.loadingTarget.classList.remove("hidden")
    this.emptyTarget.classList.add("hidden")
    this.contentTarget.classList.add("hidden")
    this.summaryTarget.classList.add("hidden")
    this.footerTarget.classList.add("hidden")
  }

  showEmpty() {
    this.loadingTarget.classList.add("hidden")
    this.emptyTarget.classList.remove("hidden")
    this.contentTarget.classList.add("hidden")
    this.summaryTarget.classList.add("hidden")
    this.footerTarget.classList.add("hidden")
  }

  renderPair() {
    const pair = this.pairs[this.currentIndex]

    if (this.deletedIds.has(pair.left.id) || this.deletedIds.has(pair.right.id)) {
      this.next()
      return
    }

    this.loadingTarget.classList.add("hidden")
    this.emptyTarget.classList.add("hidden")
    this.contentTarget.classList.remove("hidden")
    this.summaryTarget.classList.add("hidden")
    this.footerTarget.classList.remove("hidden")

    this.counterTarget.textContent = `${this.currentIndex + 1}/${this.pairs.length}`
    const progress = ((this.currentIndex + 1) / this.pairs.length) * 100
    this.progressTarget.style.width = `${progress}%`

    this.contentTarget.innerHTML = ""

    // Header row with IDs
    const headerRow = document.createElement("div")
    headerRow.className = "grid grid-cols-[1fr_auto_1fr] gap-2 mb-3 items-center"

    const leftHeader = document.createElement("div")
    leftHeader.className = "text-right"
    leftHeader.innerHTML = `<span class="text-xs text-blue-600 bg-blue-50 px-2 py-1 rounded">ID: ${pair.left.id}</span>`

    const centerHeader = document.createElement("div")
    centerHeader.className = "text-center"

    const rightHeader = document.createElement("div")
    rightHeader.className = "text-left"
    rightHeader.innerHTML = `<span class="text-xs text-purple-600 bg-purple-50 px-2 py-1 rounded">ID: ${pair.right.id}</span>`

    headerRow.appendChild(leftHeader)
    headerRow.appendChild(centerHeader)
    headerRow.appendChild(rightHeader)
    this.contentTarget.appendChild(headerRow)

    // Fields comparison
    const fields = [
      { label: "날짜", key: "date", editable: false },
      { label: "가맹점", key: "merchant", editable: true },
      { label: "설명", key: "description", editable: true },
      { label: "금액", key: "amount", editable: false, format: "currency" },
      { label: "카테고리", key: "category", editable: false },
      { label: "금융기관", key: "institution", editable: false },
      { label: "메모", key: "notes", editable: true }
    ]

    const fieldsContainer = document.createElement("div")
    fieldsContainer.className = "space-y-1"

    fields.forEach(field => {
      const leftVal = pair.left[field.key]
      const rightVal = pair.right[field.key]
      const isDifferent = leftVal !== rightVal

      const row = document.createElement("div")
      row.className = `grid grid-cols-[1fr_80px_1fr] gap-2 items-center py-2 px-3 rounded ${isDifferent ? "bg-amber-50" : ""}`
      row.dataset.fieldKey = field.key

      // Left value
      const leftCell = document.createElement("div")
      leftCell.className = "text-right"
      leftCell.appendChild(this.createValueCell(pair.left, field, "left", isDifferent))

      // Center label
      const centerCell = document.createElement("div")
      centerCell.className = `text-center text-sm text-gray-500 ${isDifferent ? "font-semibold text-amber-700" : ""}`
      centerCell.textContent = field.label

      // Right value
      const rightCell = document.createElement("div")
      rightCell.className = "text-left"
      rightCell.appendChild(this.createValueCell(pair.right, field, "right", isDifferent))

      row.appendChild(leftCell)
      row.appendChild(centerCell)
      row.appendChild(rightCell)
      fieldsContainer.appendChild(row)
    })

    this.contentTarget.appendChild(fieldsContainer)
  }

  createValueCell(tx, field, side, isDifferent) {
    const container = document.createElement("div")
    container.className = `flex items-center gap-1 ${side === "left" ? "justify-end" : "justify-start"}`
    container.dataset.side = side
    container.dataset.txId = tx.id

    const displayValue = field.format === "currency"
      ? this.formatCurrency(tx[field.key])
      : (tx[field.key] || "-")

    if (field.editable) {
      // Edit icon (left side only shows on left, right side only shows on right)
      if (side === "right") {
        const editIcon = document.createElement("span")
        editIcon.className = "text-gray-400 hover:text-gray-600 cursor-pointer"
        editIcon.innerHTML = `<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"></path></svg>`
        editIcon.addEventListener("click", () => this.startEdit(container, tx, field, side))
        container.appendChild(editIcon)
      }

      // Display value (clickable)
      const valueSpan = document.createElement("span")
      valueSpan.className = `text-sm text-gray-900 cursor-pointer hover:bg-gray-100 px-1 rounded ${isDifferent ? "font-semibold" : ""}`
      valueSpan.textContent = displayValue
      valueSpan.dataset.display = "true"
      valueSpan.addEventListener("click", () => this.startEdit(container, tx, field, side))
      container.appendChild(valueSpan)

      if (side === "left") {
        const editIcon = document.createElement("span")
        editIcon.className = "text-gray-400 hover:text-gray-600 cursor-pointer"
        editIcon.innerHTML = `<svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"></path></svg>`
        editIcon.addEventListener("click", () => this.startEdit(container, tx, field, side))
        container.appendChild(editIcon)
      }

      // Editor (hidden initially)
      const editorDiv = document.createElement("div")
      editorDiv.className = "hidden flex items-center gap-1"
      editorDiv.dataset.editor = "true"

      const input = document.createElement("input")
      input.type = "text"
      input.value = tx[field.key] || ""
      input.className = "text-sm border-gray-300 rounded px-1 py-0.5 w-28 focus:ring-1 focus:ring-indigo-500"
      input.dataset.input = "true"

      const saveBtn = document.createElement("button")
      saveBtn.className = "text-green-600 hover:text-green-800"
      saveBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path></svg>`
      saveBtn.addEventListener("click", () => this.saveEdit(container, tx, field, side))

      const cancelBtn = document.createElement("button")
      cancelBtn.className = "text-gray-400 hover:text-gray-600"
      cancelBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>`
      cancelBtn.addEventListener("click", () => this.cancelEdit(container))

      input.addEventListener("keydown", (e) => {
        if (e.key === "Enter") {
          e.preventDefault()
          e.stopPropagation()
          this.saveEdit(container, tx, field, side)
        } else if (e.key === "Escape") {
          e.preventDefault()
          e.stopPropagation()
          this.cancelEdit(container)
        }
      })

      editorDiv.appendChild(input)
      editorDiv.appendChild(saveBtn)
      editorDiv.appendChild(cancelBtn)
      container.appendChild(editorDiv)
    } else {
      const valueSpan = document.createElement("span")
      valueSpan.className = `text-sm text-gray-900 ${isDifferent ? "font-semibold" : ""}`
      valueSpan.textContent = displayValue
      container.appendChild(valueSpan)
    }

    return container
  }

  startEdit(fieldDiv, tx, field, side) {
    // Close any other open editors
    this.closeAllEditors()

    const display = fieldDiv.querySelector('[data-display="true"]')
    const editIcon = fieldDiv.querySelector('.text-gray-400')
    const editor = fieldDiv.querySelector('[data-editor="true"]')
    const input = fieldDiv.querySelector('[data-input="true"]')

    if (display) display.classList.add("hidden")
    if (editIcon) editIcon.classList.add("hidden")
    if (editor) editor.classList.remove("hidden")
    if (input) {
      input.value = tx[field.key] || ""
      input.focus()
      input.select()
    }

    this.editingField = { fieldDiv, tx, field, side }
  }

  closeAllEditors() {
    this.contentTarget.querySelectorAll('[data-editor="true"]').forEach(editor => {
      editor.classList.add("hidden")
    })
    this.contentTarget.querySelectorAll('[data-display="true"]').forEach(display => {
      display.classList.remove("hidden")
    })
    this.contentTarget.querySelectorAll('.text-gray-400.hidden').forEach(icon => {
      icon.classList.remove("hidden")
    })
    this.editingField = null
  }

  cancelEdit(fieldDiv) {
    const display = fieldDiv.querySelector('[data-display="true"]')
    const editIcon = fieldDiv.querySelector('.text-gray-400')
    const editor = fieldDiv.querySelector('[data-editor="true"]')

    if (display) display.classList.remove("hidden")
    if (editIcon) editIcon.classList.remove("hidden")
    if (editor) editor.classList.add("hidden")

    this.editingField = null
  }

  async saveEdit(fieldDiv, tx, field, side) {
    const input = fieldDiv.querySelector('[data-input="true"]')
    const newValue = input.value.trim()
    const oldValue = tx[field.key] || ""

    if (newValue === oldValue) {
      this.cancelEdit(fieldDiv)
      return
    }

    input.disabled = true

    try {
      // Build URL for inline_update
      const url = tx.delete_url.replace(/\/?$/, "/inline_update")

      const response = await fetch(url, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ field: field.key, value: newValue })
      })

      if (!response.ok) throw new Error("Update failed")

      // Update local data
      tx[field.key] = newValue
      this.hasEdited = true

      // Re-render the pair to update highlights
      this.renderPair()

    } catch (error) {
      console.error("Error saving edit:", error)
      input.disabled = false
      fieldDiv.classList.add("bg-red-100")
      setTimeout(() => fieldDiv.classList.remove("bg-red-100"), 1000)
    }
  }

  formatCurrency(amount) {
    return `₩${parseInt(amount).toLocaleString()}`
  }

  async keepLeft() {
    const pair = this.pairs[this.currentIndex]
    await this.deleteTx(pair.right)
    this.recordAction("keepLeft", pair.right.id, pair.right.restore_url)
    this.next()
  }

  async keepRight() {
    const pair = this.pairs[this.currentIndex]
    await this.deleteTx(pair.left)
    this.recordAction("keepRight", pair.left.id, pair.left.restore_url)
    this.next()
  }

  keepBoth() {
    this.stats.skipped++
    this.recordAction("keepBoth", null, null)
    this.next()
  }

  skip() {
    this.keepBoth()
  }

  async deleteTx(tx) {
    try {
      const response = await fetch(tx.delete_url, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        }
      })

      if (response.ok) {
        this.deletedIds.add(tx.id)
        this.stats.deleted++
      }
    } catch (error) {
      console.error("Error deleting transaction:", error)
    }
  }

  async undo() {
    if (!this.lastAction) return

    const { pairIndex, decision, deletedId, restoreUrl } = this.lastAction

    if (deletedId && restoreUrl) {
      try {
        const response = await fetch(restoreUrl, {
          method: "PATCH",
          headers: {
            "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
            "Accept": "application/json"
          }
        })

        if (response.ok) {
          this.deletedIds.delete(deletedId)
          this.stats.deleted--
        }
      } catch (error) {
        console.error("Error restoring transaction:", error)
        return
      }
    } else {
      this.stats.skipped--
    }

    this.lastAction = null
    this.disableUndoButton()

    this.currentIndex = pairIndex
    this.renderPair()
  }

  recordAction(decision, deletedId, restoreUrl) {
    this.lastAction = {
      pairIndex: this.currentIndex,
      decision,
      deletedId,
      restoreUrl
    }
    this.enableUndoButton()
  }

  enableUndoButton() {
    this.undoBtnTarget.disabled = false
    this.undoBtnTarget.classList.remove("text-gray-300", "opacity-50", "cursor-not-allowed")
    this.undoBtnTarget.classList.add("text-gray-600", "hover:text-gray-900", "hover:bg-gray-100", "cursor-pointer")
  }

  disableUndoButton() {
    this.undoBtnTarget.disabled = true
    this.undoBtnTarget.classList.add("text-gray-300", "opacity-50", "cursor-not-allowed")
    this.undoBtnTarget.classList.remove("text-gray-600", "hover:text-gray-900", "hover:bg-gray-100", "cursor-pointer")
  }

  next() {
    this.currentIndex++

    if (this.currentIndex >= this.pairs.length) {
      this.showSummary()
    } else {
      this.renderPair()
    }
  }

  showSummary() {
    this.contentTarget.classList.add("hidden")
    this.footerTarget.classList.add("hidden")
    this.summaryTarget.classList.remove("hidden")

    const kept = this.pairs.length - this.stats.deleted

    this.summaryTarget.innerHTML = ""

    const summaryDiv = document.createElement("div")
    summaryDiv.className = "text-center py-8"

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
    svg.setAttribute("class", "mx-auto h-16 w-16 text-green-500 mb-4")
    svg.setAttribute("fill", "none")
    svg.setAttribute("stroke", "currentColor")
    svg.setAttribute("viewBox", "0 0 24 24")
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.setAttribute("stroke-linecap", "round")
    path.setAttribute("stroke-linejoin", "round")
    path.setAttribute("stroke-width", "2")
    path.setAttribute("d", "M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z")
    svg.appendChild(path)

    const h3 = document.createElement("h3")
    h3.className = "text-xl font-semibold text-gray-900 mb-2"
    h3.textContent = "중복 검사 완료"

    const p = document.createElement("p")
    p.className = "text-gray-600 mb-6"
    p.textContent = `총 ${this.pairs.length}개 쌍을 검토했습니다`

    const statsGrid = document.createElement("div")
    statsGrid.className = "grid grid-cols-3 gap-4 max-w-md mx-auto mb-6"

    const deletedStat = this.createStatBox(this.stats.deleted, "삭제됨", "red")
    const keptStat = this.createStatBox(kept, "유지됨", "green")
    const skippedStat = this.createStatBox(this.stats.skipped, "건너뛰기", "gray")

    statsGrid.appendChild(deletedStat)
    statsGrid.appendChild(keptStat)
    statsGrid.appendChild(skippedStat)

    const closeBtn = document.createElement("button")
    closeBtn.className = "px-6 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
    closeBtn.textContent = "닫기"
    closeBtn.addEventListener("click", () => this.close())

    summaryDiv.appendChild(svg)
    summaryDiv.appendChild(h3)
    summaryDiv.appendChild(p)
    summaryDiv.appendChild(statsGrid)
    summaryDiv.appendChild(closeBtn)

    this.summaryTarget.appendChild(summaryDiv)
  }

  createStatBox(value, label, color) {
    const box = document.createElement("div")
    box.className = `bg-${color}-50 rounded-lg p-4`

    const valueDiv = document.createElement("div")
    valueDiv.className = `text-2xl font-bold text-${color}-600`
    valueDiv.textContent = value

    const labelDiv = document.createElement("div")
    labelDiv.className = "text-sm text-gray-600"
    labelDiv.textContent = label

    box.appendChild(valueDiv)
    box.appendChild(labelDiv)

    return box
  }

  handleKeydown = (event) => {
    // Ignore keyboard shortcuts when editing
    if (this.editingField) return

    if (!this.contentTarget.classList.contains("hidden")) {
      switch (event.key) {
        case "ArrowLeft":
          event.preventDefault()
          this.keepLeft()
          break
        case "ArrowRight":
          event.preventDefault()
          this.keepRight()
          break
        case "b":
        case "B":
          event.preventDefault()
          this.keepBoth()
          break
        case "s":
        case "S":
          event.preventDefault()
          this.skip()
          break
        case "z":
        case "Z":
          event.preventDefault()
          this.undo()
          break
        case "Escape":
          event.preventDefault()
          this.close()
          break
      }
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    }
  }
}
