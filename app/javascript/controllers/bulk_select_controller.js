import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "actions", "count", "ids", "selectAll"]

  connect() {
    this.updateUI()
  }

  toggle() {
    this.updateUI()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
    })
    this.updateUI()
  }

  updateUI() {
    const selected = this.checkboxTargets.filter(cb => cb.checked)
    const count = selected.length

    if (this.hasActionsTarget) {
      if (count > 0) {
        this.actionsTarget.style.display = 'flex'
        if (this.hasCountTarget) {
          this.countTarget.textContent = count
        }

        // Update hidden input with selected IDs
        if (this.hasIdsTarget) {
          this.idsTarget.value = selected.map(cb => cb.value).join(',')
        }
      } else {
        this.actionsTarget.style.display = 'none'
      }
    }

    // Update select all checkbox state
    if (this.hasSelectAllTarget && this.checkboxTargets.length > 0) {
      const allChecked = this.checkboxTargets.every(cb => cb.checked)
      const someChecked = this.checkboxTargets.some(cb => cb.checked)
      this.selectAllTarget.checked = allChecked
      this.selectAllTarget.indeterminate = someChecked && !allChecked
    }
  }
}
