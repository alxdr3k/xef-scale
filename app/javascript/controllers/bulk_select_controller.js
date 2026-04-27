import { Controller } from "@hotwired/stimulus"

// 행 선택을 차단할 인터랙티브 요소: 실제로 클릭 동작이 있는 요소만 포함
// wrapper div (data-controller="inline-edit" 등)는 제외해야 빈 영역 클릭이 행 선택으로 동작함
const INTERACTIVE_SELECTOR = [
  'select', 'button', 'a', 'input', 'textarea', 'label'
].join(', ')

export default class extends Controller {
  static targets = [
    "row", "floatingBar", "floatingCount", "ids",
    "selectAllLabel", "moreMenu",
    "toolbar", "toolbarDefault", "toolbarSelected",
    "toolbarCount", "toolbarCheckbox"
  ]

  connect() {
    this.selectedIds = new Set()
    this.lastClickedIndex = -1
    this.updateUI()
  }

  // 선택 가능한 행만 필터링
  get selectableRows() {
    return this.rowTargets.filter(
      r => r.dataset.deleted !== "true" && r.dataset.transactionId
    )
  }

  // 행 클릭 시 선택 토글 (Shift+클릭으로 범위 선택)
  toggleRow(event) {
    if (event.target.closest(INTERACTIVE_SELECTOR)) return

    const row = event.currentTarget
    const id = row.dataset.transactionId
    if (!id || row.dataset.deleted === "true") return

    const selectableRows = this.selectableRows
    const currentIndex = selectableRows.indexOf(row)
    if (currentIndex === -1) return

    if (event.shiftKey && this.lastClickedIndex !== -1) {
      // Shift+클릭: 범위 선택 (텍스트 선택 방지)
      event.preventDefault()
      window.getSelection()?.removeAllRanges()

      const start = Math.min(this.lastClickedIndex, currentIndex)
      const end = Math.max(this.lastClickedIndex, currentIndex)

      for (let i = start; i <= end; i++) {
        const r = selectableRows[i]
        const rid = r.dataset.transactionId
        if (rid) {
          this.selectedIds.add(rid)
          r.classList.add("selected")
        }
      }
    } else {
      // 일반 클릭: 토글
      if (this.selectedIds.has(id)) {
        this.selectedIds.delete(id)
        row.classList.remove("selected")
      } else {
        this.selectedIds.add(id)
        row.classList.add("selected")
      }
    }

    this.lastClickedIndex = currentIndex
    this.updateUI()
  }

  selectAll() {
    this.selectableRows.forEach(row => {
      const id = row.dataset.transactionId
      this.selectedIds.add(id)
      row.classList.add("selected")
    })
    this.updateUI()
  }

  deselectAll() {
    this.selectedIds.clear()
    this.rowTargets.forEach(row => row.classList.remove("selected"))
    this.updateUI()
  }

  toggleSelectAll() {
    const selectableRows = this.selectableRows
    const allSelected = selectableRows.length > 0 &&
      selectableRows.every(r => this.selectedIds.has(r.dataset.transactionId))

    if (allSelected) {
      this.deselectAll()
    } else {
      this.selectAll()
    }
  }

  // 더보기 메뉴 토글
  toggleMore() {
    if (!this.hasMoreMenuTarget) return
    this.moreMenuTarget.classList.toggle("hidden")
  }

  closeMore(event) {
    if (!this.hasMoreMenuTarget) return
    // 이벤트 핸들러로 호출된 경우: 메뉴 외부 클릭 시에만 닫기
    if (event?.target) {
      if (event.target.closest('[data-bulk-select-target="moreMenu"]') ||
          event.target.closest('[data-action*="toggleMore"]')) {
        return
      }
    }
    this.moreMenuTarget.classList.add("hidden")
  }

  // 일괄 액션
  deleteSelected() {
    if (this.selectedIds.size === 0) return
    if (!confirm(`선택한 ${this.selectedIds.size}개의 결제를 삭제하시겠습니까?`)) return
    this.submitBulkAction("delete")
  }

  discardSelected() {
    if (this.selectedIds.size === 0) return
    if (!confirm(`선택한 ${this.selectedIds.size}개의 업로드를 취소하시겠습니까?`)) return
    this.submitBulkAction("discard")
  }

  markAllowance() {
    if (this.selectedIds.size === 0) return
    this.submitBulkAction("mark_allowance")
    this.closeMore()
  }

  unmarkAllowance() {
    if (this.selectedIds.size === 0) return
    this.submitBulkAction("unmark_allowance")
    this.closeMore()
  }

  changeCategory(event) {
    // 버튼의 부모(flex container) 내 select 찾기
    const container = event.currentTarget.closest('.flex')
    const select = container?.querySelector('select[name="category_id"]')
      || this.element.querySelector('select[name="category_id"]')
    if (!select || !select.value) return
    this.submitBulkAction("change_category", { category_id: select.value })
    this.closeMore()
  }

  submitBulkAction(action, extraParams = {}) {
    const form = this.element.querySelector('form[data-bulk-form]')
    if (!form) return

    // IDs 설정
    if (this.hasIdsTarget) this.idsTarget.value = Array.from(this.selectedIds).join(",")

    // 액션 설정
    const actionInput = form.querySelector('[name="bulk_action"]')
    if (actionInput) actionInput.value = action

    // 추가 파라미터 설정
    for (const [key, value] of Object.entries(extraParams)) {
      let input = form.querySelector(`[name="${key}"]`)
      if (!input) {
        input = document.createElement("input")
        input.type = "hidden"
        input.name = key
        form.appendChild(input)
      }
      input.value = value
    }

    form.submit()
  }

  updateUI() {
    const count = this.selectedIds.size
    const selectableRows = this.selectableRows
    const allSelected = selectableRows.length > 0 &&
      selectableRows.every(r => this.selectedIds.has(r.dataset.transactionId))

    // 툴바 모드: 선택 상태에 따라 default/selected 전환
    if (this.hasToolbarDefaultTarget && this.hasToolbarSelectedTarget) {
      if (count > 0) {
        this.toolbarDefaultTarget.classList.add("hidden")
        this.toolbarSelectedTarget.classList.remove("hidden")
      } else {
        this.toolbarDefaultTarget.classList.remove("hidden")
        this.toolbarSelectedTarget.classList.add("hidden")
      }
    }

    // 툴바 카운트
    if (this.hasToolbarCountTarget) {
      this.toolbarCountTarget.textContent = count
    }

    // 툴바 체크박스 상태
    if (this.hasToolbarCheckboxTarget) {
      const cb = this.toolbarCheckboxTarget
      if (count === 0) {
        cb.checked = false
        cb.indeterminate = false
      } else if (allSelected) {
        cb.checked = true
        cb.indeterminate = false
      } else {
        cb.checked = false
        cb.indeterminate = true
      }
    }

    // 플로팅 바 표시/숨김 (하위 호환)
    if (this.hasFloatingBarTarget) {
      const visible = count > 0
      if (visible) {
        this.floatingBarTarget.classList.remove("translate-y-20", "opacity-0", "pointer-events-none")
        this.floatingBarTarget.classList.add("translate-y-0", "opacity-100")
      } else {
        this.floatingBarTarget.classList.add("translate-y-20", "opacity-0", "pointer-events-none")
        this.floatingBarTarget.classList.remove("translate-y-0", "opacity-100")
      }
      this.element.classList.toggle("pb-20", visible)
    }

    // 카운트 업데이트 (하위 호환)
    if (this.hasFloatingCountTarget) {
      this.floatingCountTarget.textContent = count
    }

    // IDs 업데이트
    if (this.hasIdsTarget) {
      this.idsTarget.value = Array.from(this.selectedIds).join(",")
    }

    // 전체 선택 라벨 업데이트 (하위 호환)
    if (this.hasSelectAllLabelTarget) {
      this.selectAllLabelTarget.textContent = allSelected ? "전체 해제" : "전체 선택"
    }
  }
}
