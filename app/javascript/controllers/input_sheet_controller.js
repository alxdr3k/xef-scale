import { Controller } from "@hotwired/stimulus"

// InputSheetController — 3-way 입력 시트 (ADR-0004, Phase 3.3).
//
// 검토함 / 입력 기록 페이지에서 "+ 새로 가져오기" 버튼이 시트를 연다.
// 데스크탑은 중앙 modal, 모바일은 bottom sheet (Tailwind 반응형 클래스로).
//
// open  — backdrop+sheet 보이기, body scroll 잠금.
// close — backdrop+sheet 숨김, body scroll 복원.
// handleKeydown — Esc 키 처리.
export default class extends Controller {
  static targets = ["backdrop", "sheet"]

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
}
