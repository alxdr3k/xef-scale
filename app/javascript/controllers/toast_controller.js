import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "progress"]
  static values = {
    type: { type: String, default: "success" },
    duration: { type: Number, default: 4000 }
  }

  // Duration by type (ms)
  static DURATIONS = {
    success: 4000,
    info: 4000,
    warning: 6000,
    error: 0  // Never auto-dismiss
  }

  connect() {
    // Set duration based on type if not explicitly set
    if (!this.element.dataset.toastDurationValue) {
      this.durationValue = this.constructor.DURATIONS[this.typeValue] || 4000
    }

    // Entry animation
    this.element.classList.add("translate-x-full", "opacity-0")
    requestAnimationFrame(() => {
      this.element.classList.remove("translate-x-full", "opacity-0")
    })

    // Start auto-dismiss timer if applicable
    if (this.durationValue > 0) {
      this.startTimer()
    }

    // ESC key handler
    this.boundEscHandler = this.handleEsc.bind(this)
    document.addEventListener("keydown", this.boundEscHandler)
  }

  disconnect() {
    this.clearTimer()
    document.removeEventListener("keydown", this.boundEscHandler)
  }

  startTimer() {
    this.remainingTime = this.durationValue
    this.startTime = Date.now()

    // Start progress bar animation
    if (this.hasProgressTarget) {
      this.progressTarget.style.transitionDuration = `${this.durationValue}ms`
      requestAnimationFrame(() => {
        this.progressTarget.style.width = "0%"
      })
    }

    this.timerId = setTimeout(() => {
      this.dismiss()
    }, this.durationValue)
  }

  pauseTimer() {
    if (!this.timerId) return

    clearTimeout(this.timerId)
    this.timerId = null

    // Calculate remaining time
    const elapsed = Date.now() - this.startTime
    this.remainingTime = Math.max(0, this.remainingTime - elapsed)

    // Pause progress bar
    if (this.hasProgressTarget) {
      const currentWidth = this.progressTarget.offsetWidth
      const parentWidth = this.progressTarget.parentElement.offsetWidth
      const percentage = (currentWidth / parentWidth) * 100
      this.progressTarget.style.transitionDuration = "0ms"
      this.progressTarget.style.width = `${percentage}%`
    }
  }

  resumeTimer() {
    if (this.timerId || this.remainingTime <= 0) return

    this.startTime = Date.now()

    // Resume progress bar
    if (this.hasProgressTarget) {
      this.progressTarget.style.transitionDuration = `${this.remainingTime}ms`
      requestAnimationFrame(() => {
        this.progressTarget.style.width = "0%"
      })
    }

    this.timerId = setTimeout(() => {
      this.dismiss()
    }, this.remainingTime)
  }

  clearTimer() {
    if (this.timerId) {
      clearTimeout(this.timerId)
      this.timerId = null
    }
  }

  mouseEnter() {
    this.pauseTimer()
  }

  mouseLeave() {
    this.resumeTimer()
  }

  handleEsc(event) {
    if (event.key === "Escape") {
      this.dismiss()
    }
  }

  close(event) {
    event?.preventDefault()
    this.dismiss()
  }

  dismiss() {
    this.clearTimer()

    // Exit animation
    this.element.classList.add("opacity-0", "scale-95")

    setTimeout(() => {
      this.element.remove()
    }, 200)
  }
}
