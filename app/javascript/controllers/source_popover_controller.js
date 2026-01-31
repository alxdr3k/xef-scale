import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["popover"]
  static values = {
    filename: String,
    sourceType: String,
    uploadedAt: String,
    sessionUrl: String
  }

  toggle(event) {
    event.stopPropagation()
    const popover = this.popoverTarget

    if (popover.classList.contains("hidden")) {
      this._position()
      popover.classList.remove("hidden")
    } else {
      popover.classList.add("hidden")
    }
  }

  close() {
    this.popoverTarget.classList.add("hidden")
  }

  navigate(event) {
    // 링크 클릭 시 Turbo 네비게이션 허용 (이벤트 전파만 중단)
    const url = event.currentTarget.href
    this.close()
    Turbo.visit(url)
    event.preventDefault()
  }

  _position() {
    const trigger = this.element
    const popover = this.popoverTarget
    const rect = trigger.getBoundingClientRect()

    // 아래쪽에 표시
    let top = rect.bottom + 4
    let left = rect.left

    // 화면 밖으로 나가면 위로
    const popoverH = 120
    if (top + popoverH > window.innerHeight - 8) {
      top = rect.top - popoverH - 4
    }

    // 오른쪽 넘침 방지
    const popoverW = 224 // w-56
    if (left + popoverW > window.innerWidth - 8) {
      left = window.innerWidth - popoverW - 8
    }

    popover.style.top = `${Math.max(8, top)}px`
    popover.style.left = `${Math.max(8, left)}px`
  }

  connect() {
    this._outsideHandler = (event) => {
      if (this.popoverTarget.classList.contains("hidden")) return
      if (this.element.contains(event.target)) return
      this.close()
    }
    document.addEventListener("click", this._outsideHandler)
  }

  disconnect() {
    document.removeEventListener("click", this._outsideHandler)
  }
}
