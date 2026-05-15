import { Controller } from "@hotwired/stimulus"

// CategoryLearningSuggestionController — ADR-0007 §4 explicit opt-in 학습.
//
// quick_update_category turbo_stream로 추가된 inline suggestion row의 [예/아니오]
// 버튼을 처리한다.
//
// accept  — POST urlValue, body { category_id: categoryIdValue }. 응답은
//           turbo_stream으로 본 row를 제거.
// dismiss — 본 row를 DOM에서 즉시 제거. 서버 호출 없음(상태 미보존).
export default class extends Controller {
  static values = {
    url: String,
    categoryId: Number
  }

  async accept(event) {
    event.preventDefault()
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute("content")

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "text/vnd.turbo-stream.html",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({ category_id: this.categoryIdValue })
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      } else {
        // 서버가 거부한 경우(권한/검증 실패) 사용자가 다시 시도할 수 있게
        // suggestion row는 그대로 둔다.
        console.error("Learning suggestion accept failed:", response.status)
      }
    } catch (error) {
      console.error("Learning suggestion accept failed:", error)
    }
  }

  dismiss(event) {
    event.preventDefault()
    this.element.remove()
  }
}
