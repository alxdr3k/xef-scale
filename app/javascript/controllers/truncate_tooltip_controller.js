import { Controller } from "@hotwired/stimulus"

// Displays a tooltip only when the element's text is truncated (overflow).
// Appends tooltip to document.body with fixed positioning to avoid overflow:hidden clipping.
//
// Usage:
//   <span data-controller="truncate-tooltip"
//         data-action="mouseenter->truncate-tooltip#show mouseleave->truncate-tooltip#hide"
//         class="block truncate">
//     Long text here...
//   </span>
export default class extends Controller {
  show() {
    this.hide()
    if (this.element.scrollWidth <= this.element.clientWidth) return

    this.tooltip = document.createElement("div")
    this.tooltip.textContent = this.element.textContent.trim()
    this.tooltip.className =
      "fixed px-2 py-1 text-[11px] rounded bg-gray-800 text-white whitespace-nowrap pointer-events-none z-50 transition-opacity"
    document.body.appendChild(this.tooltip)

    const rect = this.element.getBoundingClientRect()
    this.tooltip.style.left = `${rect.left + rect.width / 2 - this.tooltip.offsetWidth / 2}px`
    this.tooltip.style.top = `${rect.top - this.tooltip.offsetHeight - 4}px`
  }

  hide() {
    this.tooltip?.remove()
    this.tooltip = null
  }

  disconnect() {
    this.tooltip?.remove()
  }
}
