import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "chevron", "currentDisplay", "yearDisplay", "currentYear", "currentMonth", "basePath"]

  connect() {
    this.year = parseInt(this.currentYearTarget.value)
    this.month = parseInt(this.currentMonthTarget.value)
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

  previousYear(event) {
    event.stopPropagation()
    this.year--
    this.updateYearDisplay()
  }

  nextYear(event) {
    event.stopPropagation()
    this.year++
    this.updateYearDisplay()
  }

  selectMonth(event) {
    event.stopPropagation()
    this.month = parseInt(event.currentTarget.dataset.month)
    this.navigate()
  }

  updateYearDisplay() {
    this.yearDisplayTarget.textContent = `${this.year}년`
  }

  navigate() {
    // Build the URL with year and month parameters
    const url = `${this.basePath}?year=${this.year}&month=${this.month}`
    // Navigate using Turbo
    window.Turbo.visit(url)
  }
}
