import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown"]

  connect() {
    // Close on outside click
    this.boundCloseOnOutsideClick = this.closeOnOutsideClick.bind(this)
    document.addEventListener('click', this.boundCloseOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener('click', this.boundCloseOnOutsideClick)
  }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.classList.toggle('hidden')
  }

  closeOnOutsideClick(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.classList.add('hidden')
    }
  }

  markRead(event) {
    const notificationId = event.currentTarget.dataset.notificationId
    if (notificationId) {
      fetch(`/notifications/${notificationId}/mark_read`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Accept': 'application/json'
        }
      }).then(() => {
        // Optionally update badge count
        this.updateBadge()
      })
    }
  }

  updateBadge() {
    fetch('/notifications/unread_count', {
      headers: {
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      const badge = document.getElementById('notification-badge')
      if (badge) {
        if (data.count > 0) {
          badge.textContent = data.count > 9 ? '9+' : data.count
          badge.style.display = 'flex'
        } else {
          badge.style.display = 'none'
        }
      }
    })
  }
}
