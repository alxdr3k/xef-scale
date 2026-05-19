import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "chevron", "currentDisplay", "yearDisplay", "currentYear", "currentMonth", "basePath"]
  static values = {
    // "년" 같은 한국어 접미사도 view에서 t() 결과로 주입한다. defaultValue 폴백으로
    // 마운트 view가 누락해도 깨지진 않게 — 본 컨트롤러는 i18n-allow가 아닌
    // 사용자 가시 텍스트를 직접 박지 않는다.
    yearSuffix: { type: String, default: "" }
  }

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
    this.yearDisplayTarget.textContent = `${this.year}${this.yearSuffixValue}`
  }

  navigate() {
    // Build the URL with year and month parameters
    const url = `${this.basePath}?year=${this.year}&month=${this.month}`
    // Navigate using Turbo
    window.Turbo.visit(url)
  }
}
