import { Controller } from "@hotwired/stimulus"

// InputSheetController — 3-way 입력 시트 (ADR-0004, Phase 3.3).
//
// 검토함 / 입력 기록 페이지에서 "+ 새로 가져오기" 버튼이 시트를 연다.
// 데스크탑은 중앙 modal, 모바일은 bottom sheet (Tailwind 반응형 클래스로).
//
// open  — backdrop+sheet 보이기, body scroll 잠금.
// close — backdrop+sheet 숨김, body scroll 복원.
// handleKeydown — Esc 키 처리.
//
// Turbo snapshot caching: 시트가 열린 채로 form submit·직접 입력 링크 등으로
// 페이지를 떠나면 Turbo가 열린 상태를 캐시해 뒤로 가기 시 stale 상태로
// 복원될 수 있다. `turbo:before-cache`에서 강제로 close하고 body 잠금을
// 해제해 캐시된 스냅샷이 깨끗하게 남도록 한다.
export default class extends Controller {
  static targets = ["backdrop", "sheet"]

  initialize() {
    this.resetBeforeCache = this.resetBeforeCache.bind(this)
  }

  connect() {
    document.addEventListener("turbo:before-cache", this.resetBeforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.resetBeforeCache)
    // Stimulus가 분리될 때 body scroll 잠금이 새는 일이 없도록 명시 해제.
    document.body.classList.remove("overflow-hidden")
  }

  open(event) {
    event?.preventDefault()
    this.backdropTarget.classList.remove("hidden")
    this.sheetTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close(event) {
    event?.preventDefault()
    this.backdropTarget.classList.add("hidden")
    this.sheetTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  handleKeydown(event) {
    if (event.key === "Escape" && !this.sheetTarget.classList.contains("hidden")) {
      this.close(event)
    }
  }

  resetBeforeCache() {
    // 캐시되는 스냅샷에는 닫힌 상태가 저장돼야 한다 (DOM 클래스 직접 조작).
    // close()는 event.preventDefault()를 부르므로 여기서는 클래스만 정리.
    this.backdropTarget?.classList.add("hidden")
    this.sheetTarget?.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }
}

