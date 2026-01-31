import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["hidden", "swatch", "customInput", "customButton"]

  connect() {
    this._highlightCurrent()
  }

  selectPreset(event) {
    const color = event.currentTarget.dataset.color
    this.hiddenTarget.value = color
    this._highlightCurrent()
  }

  openCustom() {
    this.customInputTarget.click()
  }

  customChanged() {
    const color = this.customInputTarget.value
    this.hiddenTarget.value = color
    this._highlightCurrent()
  }

  _highlightCurrent() {
    const current = this.hiddenTarget.value.toLowerCase()

    this.swatchTargets.forEach(el => {
      const isSelected = el.dataset.color.toLowerCase() === current
      el.classList.toggle("ring-2", isSelected)
      el.classList.toggle("ring-offset-2", isSelected)
      el.classList.toggle("ring-gray-900", isSelected)
      // show checkmark
      const check = el.querySelector("[data-check]")
      if (check) check.classList.toggle("hidden", !isSelected)
    })

    // Update custom button color if current isn't a preset
    const isPreset = this.swatchTargets.some(el => el.dataset.color.toLowerCase() === current)
    this.customInputTarget.value = current
    const btn = this.customButtonTarget
    if (!isPreset && current) {
      btn.style.backgroundColor = current
      btn.classList.remove("bg-white")
      btn.classList.add("ring-2", "ring-offset-2", "ring-gray-900")
      const icon = btn.querySelector("[data-custom-icon]")
      // adjust icon color for dark backgrounds
      if (icon) icon.style.color = this._isLight(current) ? "#374151" : "#ffffff"
    } else {
      btn.style.backgroundColor = ""
      btn.classList.add("bg-white")
      btn.classList.remove("ring-2", "ring-offset-2", "ring-gray-900")
      const icon = btn.querySelector("[data-custom-icon]")
      if (icon) icon.style.color = "#6b7280"
    }
  }

  _isLight(hex) {
    const c = hex.replace("#", "")
    const r = parseInt(c.substring(0, 2), 16)
    const g = parseInt(c.substring(2, 4), 16)
    const b = parseInt(c.substring(4, 6), 16)
    return (r * 299 + g * 587 + b * 114) / 1000 > 128
  }
}
