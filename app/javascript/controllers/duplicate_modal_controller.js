import { Controller } from "@hotwired/stimulus"
import DragCopyManager from "../utils/drag_copy_manager"
import { jsonPatchHeaders } from "../utils/csrf"

export default class extends Controller {
  static targets = ["modal", "content", "loading", "empty", "summary", "counter", "progress", "undoBtn", "footer"]
  static values = { url: String }

  connect() {
    this.pairs = []
    this.categories = []
    this.currentIndex = 0
    this.deletedIds = new Set()
    this.lastAction = null
    this.stats = { deleted: 0, kept: 0, skipped: 0 }
    this.editingField = null
    this.initDragManager()
  }

  initDragManager() {
    this.dragManager = new DragCopyManager({
      compatibility: {
        text: ["text"],    // Text fields can drop on any text field
        select: ["select"] // Select fields require same fieldKey check
      },
      requireSameFieldKey: ["select"], // Category can only drop on category
      classes: {
        dragging: "opacity-50",
        dropTarget: ["ring-2", "ring-indigo-400", "bg-indigo-50"]
      },
      onDrop: async (sourceData, targetData) => {
        const targetTx = targetData.context.tx

        if (targetData.fieldType === "select") {
          await this.applyDroppedCategory(targetTx, sourceData.value, sourceData.categoryName)
        } else {
          await this.applyDroppedText(targetTx, targetData.fieldKey, sourceData.value)
        }
      }
    })
  }

  disconnect() {
    if (this.dragManager) {
      this.dragManager.destroy()
    }
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
      this.categories = data.categories || []

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

    // Clean up old drag elements before re-rendering
    if (this.dragManager) {
      this.dragManager.destroy()
      this.initDragManager()
    }

    this.contentTarget.innerHTML = ""

    // Fields definition
    const fields = [
      { label: "날짜", key: "date", editable: false },
      { label: "가맹점", key: "merchant", editable: true, type: "text" },
      { label: "설명", key: "description", editable: true, type: "text" },
      { label: "금액", key: "amount", editable: false, format: "currency" },
      { label: "카테고리", key: "category", editable: true, type: "select" },
      { label: "금융기관", key: "institution", editable: false },
      { label: "메모", key: "notes", editable: true, type: "text" }
    ]

    // 3-column layout: left card | labels | right card
    const container = document.createElement("div")
    container.className = "grid grid-cols-[1fr_80px_1fr] gap-3"

    // Left card
    const leftCard = document.createElement("div")
    leftCard.className = "bg-blue-50 border-2 border-blue-300 rounded-lg p-4"

    const leftHeader = document.createElement("div")
    leftHeader.className = "text-center mb-3 pb-2 border-b border-blue-200"
    leftHeader.innerHTML = `<span class="text-xs font-medium text-blue-700">등록: ${pair.left.created_at}</span>`
    leftCard.appendChild(leftHeader)

    const leftFields = document.createElement("div")
    leftFields.className = "space-y-2"

    // Center labels
    const centerLabels = document.createElement("div")
    centerLabels.className = "flex flex-col pt-12"

    const centerSpacer = document.createElement("div")
    centerSpacer.className = "h-[22px]" // Match header height
    centerLabels.appendChild(centerSpacer)

    const labelsContainer = document.createElement("div")
    labelsContainer.className = "space-y-2"

    // Right card
    const rightCard = document.createElement("div")
    rightCard.className = "bg-violet-50 border-2 border-violet-300 rounded-lg p-4"

    const rightHeader = document.createElement("div")
    rightHeader.className = "text-center mb-3 pb-2 border-b border-violet-200"
    rightHeader.innerHTML = `<span class="text-xs font-medium text-violet-700">등록: ${pair.right.created_at}</span>`
    rightCard.appendChild(rightHeader)

    const rightFields = document.createElement("div")
    rightFields.className = "space-y-2"

    // Build fields
    fields.forEach(field => {
      const leftVal = pair.left[field.key]
      const rightVal = pair.right[field.key]
      const isDifferent = leftVal !== rightVal

      // Left value
      const leftRow = document.createElement("div")
      leftRow.className = `text-right py-1.5 px-2 rounded ${isDifferent ? "bg-amber-100 ring-1 ring-amber-300" : ""}`
      leftRow.appendChild(this.createValueCell(pair.left, field, "left", isDifferent))
      leftFields.appendChild(leftRow)

      // Center label
      const labelRow = document.createElement("div")
      labelRow.className = `text-center text-sm py-1.5 ${isDifferent ? "font-semibold text-amber-700" : "text-gray-500"}`
      labelRow.textContent = field.label
      labelsContainer.appendChild(labelRow)

      // Right value
      const rightRow = document.createElement("div")
      rightRow.className = `text-left py-1.5 px-2 rounded ${isDifferent ? "bg-amber-100 ring-1 ring-amber-300" : ""}`
      rightRow.appendChild(this.createValueCell(pair.right, field, "right", isDifferent))
      rightFields.appendChild(rightRow)
    })

    leftCard.appendChild(leftFields)
    centerLabels.appendChild(labelsContainer)
    rightCard.appendChild(rightFields)

    container.appendChild(leftCard)
    container.appendChild(centerLabels)
    container.appendChild(rightCard)

    this.contentTarget.appendChild(container)
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
      if (field.type === "select") {
        // Category select
        this.createSelectCell(container, tx, field, side, isDifferent, displayValue)
      } else {
        // Text input
        this.createTextCell(container, tx, field, side, isDifferent, displayValue)
      }
    } else {
      const valueSpan = document.createElement("span")
      valueSpan.className = `text-sm text-gray-900 ${isDifferent ? "font-semibold" : ""}`
      valueSpan.textContent = displayValue
      container.appendChild(valueSpan)
    }

    return container
  }

  createTextCell(container, tx, field, side, isDifferent, displayValue) {
    // Display value (clickable with hover underline, draggable)
    const valueSpan = document.createElement("span")
    valueSpan.className = `text-sm text-gray-900 cursor-pointer border-b border-transparent hover:border-gray-400 hover:border-dashed transition-colors ${isDifferent ? "font-semibold" : ""}`
    valueSpan.textContent = displayValue
    valueSpan.dataset.display = "true"

    valueSpan.addEventListener("click", () => this.startEdit(container, tx, field, side))

    // Use DragCopyManager for drag and drop
    this.dragManager.makeDraggableDropTarget(valueSpan, {
      fieldKey: field.key,
      fieldType: "text",
      side: side,
      value: tx[field.key] || "",
      context: { tx }
    })

    container.appendChild(valueSpan)

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
  }

  createSelectCell(container, tx, field, side, isDifferent, displayValue) {
    // Display value (clickable with hover underline, draggable)
    const valueSpan = document.createElement("span")
    valueSpan.className = `text-sm text-gray-900 cursor-pointer border-b border-transparent hover:border-gray-400 hover:border-dashed transition-colors ${isDifferent ? "font-semibold" : ""}`
    valueSpan.textContent = displayValue
    valueSpan.dataset.display = "true"

    valueSpan.addEventListener("click", () => this.startSelectEdit(container, tx, field, side))

    // Use DragCopyManager for drag and drop
    this.dragManager.makeDraggableDropTarget(valueSpan, {
      fieldKey: field.key,
      fieldType: "select",
      side: side,
      value: tx.category_id || "",
      categoryName: tx[field.key] || "",
      context: { tx }
    })

    container.appendChild(valueSpan)

    // Editor (hidden initially)
    const editorDiv = document.createElement("div")
    editorDiv.className = "hidden flex items-center gap-1"
    editorDiv.dataset.editor = "true"

    const select = document.createElement("select")
    select.className = "text-sm border-gray-300 rounded px-1 py-0.5 focus:ring-1 focus:ring-indigo-500"
    select.dataset.input = "true"

    // Add empty option
    const emptyOption = document.createElement("option")
    emptyOption.value = ""
    emptyOption.textContent = "미분류"
    select.appendChild(emptyOption)

    // Add category options
    this.categories.forEach(cat => {
      const option = document.createElement("option")
      option.value = cat.id
      option.textContent = cat.name
      if (tx.category_id === cat.id) {
        option.selected = true
      }
      select.appendChild(option)
    })

    select.addEventListener("change", () => this.saveCategoryEdit(container, tx, select.value, side))

    select.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        e.stopPropagation()
        this.cancelEdit(container)
      }
    })

    const cancelBtn = document.createElement("button")
    cancelBtn.className = "text-gray-400 hover:text-gray-600"
    cancelBtn.innerHTML = `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path></svg>`
    cancelBtn.addEventListener("click", () => this.cancelEdit(container))

    editorDiv.appendChild(select)
    editorDiv.appendChild(cancelBtn)
    container.appendChild(editorDiv)
  }

  startEdit(fieldDiv, tx, field, side) {
    // Close any other open editors
    this.closeAllEditors()

    const display = fieldDiv.querySelector('[data-display="true"]')
    const editor = fieldDiv.querySelector('[data-editor="true"]')
    const input = fieldDiv.querySelector('[data-input="true"]')

    if (display) display.classList.add("hidden")
    if (editor) editor.classList.remove("hidden")
    if (input) {
      input.value = tx[field.key] || ""
      input.focus()
      input.select()
    }

    this.editingField = { fieldDiv, tx, field, side }
  }

  startSelectEdit(fieldDiv, tx, field, side) {
    // Close any other open editors
    this.closeAllEditors()

    const display = fieldDiv.querySelector('[data-display="true"]')
    const editor = fieldDiv.querySelector('[data-editor="true"]')
    const select = fieldDiv.querySelector('select')

    if (display) display.classList.add("hidden")
    if (editor) editor.classList.remove("hidden")
    if (select) {
      select.value = tx.category_id || ""
      select.focus()
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
    this.editingField = null
  }

  cancelEdit(fieldDiv) {
    const display = fieldDiv.querySelector('[data-display="true"]')
    const editor = fieldDiv.querySelector('[data-editor="true"]')

    if (display) display.classList.remove("hidden")
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
        headers: jsonPatchHeaders(),
        body: JSON.stringify({ field: field.key, value: newValue })
      })

      if (!response.ok) throw new Error("Update failed")

      // Update local data
      tx[field.key] = newValue
      this.hasEdited = true
      this.editingField = null

      // Re-render the pair to update highlights
      this.renderPair()

    } catch (error) {
      console.error("Error saving edit:", error)
      input.disabled = false
      fieldDiv.classList.add("bg-red-100")
      setTimeout(() => fieldDiv.classList.remove("bg-red-100"), 1000)
    }
  }

  async saveCategoryEdit(fieldDiv, tx, categoryId, side) {
    const select = fieldDiv.querySelector('select')
    const oldCategoryId = tx.category_id

    if (categoryId === String(oldCategoryId) || (categoryId === "" && oldCategoryId === null)) {
      this.cancelEdit(fieldDiv)
      return
    }

    select.disabled = true

    try {
      const response = await fetch(tx.category_url, {
        method: "PATCH",
        headers: jsonPatchHeaders(),
        body: JSON.stringify({ category_id: categoryId || null })
      })

      if (!response.ok) throw new Error("Update failed")

      // Update local data
      tx.category_id = categoryId ? parseInt(categoryId) : null
      const selectedCategory = this.categories.find(c => c.id === tx.category_id)
      tx.category = selectedCategory ? selectedCategory.name : null
      this.hasEdited = true
      this.editingField = null

      // Re-render the pair to update highlights
      this.renderPair()

    } catch (error) {
      console.error("Error saving category:", error)
      select.disabled = false
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
        headers: jsonPatchHeaders()
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
          headers: jsonPatchHeaders()
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

  // Drop handlers (called by DragCopyManager)
  async applyDroppedText(tx, fieldKey, value) {
    const url = tx.delete_url.replace(/\/?$/, "/inline_update")

    try {
      const response = await fetch(url, {
        method: "PATCH",
        headers: jsonPatchHeaders(),
        body: JSON.stringify({ field: fieldKey, value: value || "" })
      })

      if (!response.ok) throw new Error("Update failed")

      // Update local data
      tx[fieldKey] = value
      this.hasEdited = true

      // Re-render the pair to reflect changes
      this.renderPair()

    } catch (error) {
      console.error("Error applying dropped text:", error)
    }
  }

  async applyDroppedCategory(tx, categoryId, categoryName) {
    try {
      const response = await fetch(tx.category_url, {
        method: "PATCH",
        headers: jsonPatchHeaders(),
        body: JSON.stringify({ category_id: categoryId || null })
      })

      if (!response.ok) throw new Error("Update failed")

      // Update local data
      tx.category_id = categoryId ? parseInt(categoryId) : null
      tx.category = categoryName || null
      this.hasEdited = true

      // Re-render the pair to reflect changes
      this.renderPair()

    } catch (error) {
      console.error("Error applying dropped category:", error)
    }
  }
}
