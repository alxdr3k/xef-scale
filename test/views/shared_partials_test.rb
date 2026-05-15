require "test_helper"

# Phase 1 follow-up partials (ADR-0003 / synthesis.md 6.3): _amount, _hero_stat,
# _context_header. 본 테스트는 partial 자체의 시맨틱 토큰 매핑·구조를 핀하고,
# 후속 Phase 에서 페이지 단위 채택 시 변경이 의도된 형태로 일어나도록 보호한다.
class SharedPartialsTest < ActionView::TestCase
  # ---------- shared/_amount ----------

  test "amount renders with default neutral tone and tabular-nums" do
    output = render(partial: "shared/amount", locals: { value: 12_345 })
    assert_match "tabular-nums", output
    assert_match "text-primary", output
    assert_match "text-amount", output
    assert_match "₩12,345", output
  end

  test "amount tone maps to semantic utility" do
    output = render(partial: "shared/amount", locals: { value: 1000, tone: :positive })
    assert_match "text-positive", output

    output = render(partial: "shared/amount", locals: { value: 1000, tone: :warning })
    assert_match "text-warning", output

    output = render(partial: "shared/amount", locals: { value: 1000, tone: :danger })
    assert_match "text-danger", output
  end

  test "amount size maps to typography token" do
    output = render(partial: "shared/amount", locals: { value: 1_234_567, size: :display })
    assert_match "text-display", output

    output = render(partial: "shared/amount", locals: { value: 1234, size: :meta })
    assert_match "text-meta", output
  end

  test "amount sign prepends + when sign requested and value positive" do
    output = render(partial: "shared/amount", locals: { value: 5000, sign: true })
    assert_match(/\+₩5,000/, output)
  end

  test "amount sign omits + when sign requested and value negative or zero" do
    output = render(partial: "shared/amount", locals: { value: -1000, sign: true })
    assert_no_match(/\+/, output)
  end

  # ---------- shared/_hero_stat ----------

  test "hero_stat renders label and value as display size" do
    output = render(partial: "shared/hero_stat", locals: {
      label: "2026년 5월 총 지출",
      value: 2_500_000
    })
    assert_match "2026년 5월 총 지출", output
    assert_match "₩2,500,000", output
    assert_match "text-display", output
    assert_match "bg-surface", output
  end

  test "hero_stat omits supporting and CTA when not provided" do
    output = render(partial: "shared/hero_stat", locals: {
      label: "지출",
      value: 100
    })
    assert_no_match "예산", output
  end

  test "hero_stat includes supporting and CTA when provided" do
    output = render(partial: "shared/hero_stat", locals: {
      label: "지출",
      value: 1000,
      supporting: "일 평균 ₩200",
      cta_label: "예산 조정",
      cta_path: "/budgets"
    })
    assert_match "일 평균 ₩200", output
    assert_match "예산 조정", output
    assert_match 'href="/budgets"', output
    assert_match "text-action", output
  end

  # ---------- shared/_context_header ----------

  test "context_header renders title with primary tone" do
    output = render(partial: "shared/context_header", locals: { title: "거래" })
    assert_match "거래", output
    assert_match "text-primary", output
    assert_match "text-title", output
  end

  test "context_header renders context as live secondary text when provided" do
    output = render(partial: "shared/context_header", locals: {
      title: "검토",
      context: "검토 대기 12건"
    })
    assert_match "검토 대기 12건", output
    assert_match "text-secondary", output
  end

  test "context_header skips context paragraph when not provided" do
    output = render(partial: "shared/context_header", locals: { title: "거래" })
    assert_no_match(/<p[^>]*>/, output)
  end
end
