import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "chevron", "currentDisplay", "rangeDisplay", "yearGrid", "basePath"]
  static values = {
    selectedYear: Number,
    startYear: Number,
    // "년" 한국어 접미사. view에서 t() 주입.
    yearSuffix: { type: String, default: "" }
  }

  connect() {
    this.selectedYear = this.selectedYearValue
    this.startYear = this.startYearValue
    this.basePath = this.basePathTarget.value

    // Close dropdown when clicking outside
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this)
    document.addEventListener('click', this.boundCloseOnClickOutside)
  }

  disconnect() {
    document.removeEventListener('click', this.boundCloseOnClickOutside)
  }

  toggle(event) {
    event.stopPropagation()
    const isHidden = this.dropdownTarget.classList.contains('hidden')

    if (isHidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.dropdownTarget.classList.remove('hidden')
    this.chevronTarget.style.transform = 'rotate(180deg)'
  }

  close() {
    this.dropdownTarget.classList.add('hidden')
    this.chevronTarget.style.transform = 'rotate(0deg)'
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.close()
    }
  }

  previousRange(event) {
    event.stopPropagation()
    this.startYear -= 12
    this.updateGrid()
  }

  nextRange(event) {
    event.stopPropagation()
    this.startYear += 12
    this.updateGrid()
  }

  selectYear(event) {
    event.stopPropagation()
    const year = parseInt(event.currentTarget.dataset.year)
    this.navigate(year)
  }

  updateGrid() {
    const endYear = this.startYear + 11
    const suffix = this.yearSuffixValue
    this.rangeDisplayTarget.textContent = `${this.startYear}${suffix} - ${endYear}${suffix}`

    // Update year buttons
    const buttons = this.yearGridTarget.querySelectorAll('button[data-year]')
    let yearIndex = this.startYear

    buttons.forEach((button) => {
      button.dataset.year = yearIndex
      button.textContent = `${yearIndex}${suffix}`

      // Phase 5 cleanup (Scope C-2): semantic 토큰. selected → filled action,
      // inactive → secondary 본문 색 + elev hover (PR #217/#218 가이드).
      if (yearIndex === this.selectedYear) {
        button.className = 'px-3 py-2 text-sm font-medium rounded-lg transition-colors bg-action text-action-on'
      } else {
        button.className = 'px-3 py-2 text-sm font-medium rounded-lg transition-colors text-secondary hover:bg-elev'
      }

      yearIndex++
    })
  }

  navigate(year) {
    const url = `${this.basePath}?year=${year}`
    window.Turbo.visit(url)
  }
}
