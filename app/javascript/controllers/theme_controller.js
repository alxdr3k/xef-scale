import { Controller } from "@hotwired/stimulus"

// ThemeController — Phase 5 다크 모드 토글 (ADR-0008).
//
// 라디오 input 변경 시:
//   1) html[data-theme]을 즉시 갱신 — 색상이 즉시 반영되어야 사용자 피드백.
//   2) 폼을 submit (Turbo) — 서버에 user.settings["theme"] 저장.
export default class extends Controller {
  static targets = ["input"]

  apply(event) {
    const value = event.target.value
    document.documentElement.dataset.theme = value
  }

  submit(event) {
    // Form 자체가 data-action="change->theme#submit"으로 트리거.
    // requestSubmit으로 Turbo가 처리.
    this.element.requestSubmit()
  }
}
