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
      // Phase 5 cleanup (Scope C-3): ring-gray-900 → ring-focus.
      // selection ring은 임의 swatch 색 위에 표시되므로 semantic focus 토큰이 적합.
      el.classList.toggle("ring-focus", isSelected)
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
      btn.classList.remove("bg-surface")
      btn.classList.add("ring-2", "ring-offset-2", "ring-focus")
      const icon = btn.querySelector("[data-custom-icon]")
      // Phase 5 cleanup (Scope C-3): swatch 위 icon은 임의 hex 색 (사용자 선택) 위에
      // 그려지므로 theme 토큰을 못 쓴다. light/dark contrast 분기는 swatch 색에 대한
      // 것이지 페이지 테마에 대한 것이 아님. raw hex는 의도된 allowlist 케이스.
      if (icon) icon.style.color = this._isLight(current) ? "#374151" : "#ffffff"
    } else {
      btn.style.backgroundColor = ""
      btn.classList.add("bg-surface")
      btn.classList.remove("ring-2", "ring-offset-2", "ring-focus")
      const icon = btn.querySelector("[data-custom-icon]")
      // custom button no color → 페이지 surface 위에 있으므로 secondary 본문 색 hint.
      // 인라인 style 대신 className로 토글해 다크 모드 동기화.
      if (icon) {
        icon.style.color = ""
        icon.classList.add("text-secondary")
      }
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
