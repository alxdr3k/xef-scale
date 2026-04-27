import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["day"]

  select(event) {
    this.dayTargets.forEach(cell => {
      cell.classList.remove("border-indigo-600", "ring-1", "ring-indigo-600")
    })
    event.currentTarget.classList.add("border-indigo-600", "ring-1", "ring-indigo-600")
  }
}
