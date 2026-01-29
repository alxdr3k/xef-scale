export function getCsrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

export function jsonPatchHeaders() {
  return {
    "Content-Type": "application/json",
    "Accept": "application/json",
    "X-CSRF-Token": getCsrfToken()
  }
}
