import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "chevron", "currentDisplay", "rangeDisplay", "yearGrid", "basePath"]
  static values = {
    selectedYear: Number,
    startYear: Number
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
    this.rangeDisplayTarget.textContent = `${this.startYear}년 - ${endYear}년`

    // Update year buttons
    const buttons = this.yearGridTarget.querySelectorAll('button[data-year]')
    let yearIndex = this.startYear

    buttons.forEach((button) => {
      button.dataset.year = yearIndex
      button.textContent = `${yearIndex}년`

      // Update styling
      if (yearIndex === this.selectedYear) {
        button.className = 'px-3 py-2 text-sm font-medium rounded-lg transition-colors bg-indigo-600 text-white'
      } else {
        button.className = 'px-3 py-2 text-sm font-medium rounded-lg transition-colors text-gray-700 hover:bg-gray-100'
      }

      yearIndex++
    })
  }

  navigate(year) {
    const url = `${this.basePath}?year=${year}`
    window.Turbo.visit(url)
  }
}
