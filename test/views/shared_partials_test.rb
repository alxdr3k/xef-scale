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

  # ---------- shared/_source_icon ----------

  test "source_icon renders manual glyph with korean aria label" do
    output = render(partial: "shared/source_icon", locals: { source_type: "manual" })
    assert_match "✍", output
    assert_match 'aria-label="수기 입력"', output
    assert_match "text-tertiary", output
  end

  test "source_icon renders distinct glyphs for text_paste and image_upload" do
    text   = render(partial: "shared/source_icon", locals: { source_type: "text_paste" })
    image  = render(partial: "shared/source_icon", locals: { source_type: "image_upload" })
    assert_match "💬", text
    assert_match 'aria-label="문자 붙여넣기"', text
    assert_match "📷", image
    assert_match 'aria-label="스크린샷"', image
  end

  test "source_icon distinguishes api and import with aria label" do
    api    = render(partial: "shared/source_icon", locals: { source_type: "api" })
    import = render(partial: "shared/source_icon", locals: { source_type: "import" })
    assert_match "🔗", api
    assert_match "🔗", import
    assert_match 'aria-label="외부 API"', api
    assert_match 'aria-label="가져오기"', import
  end

  test "source_icon renders nothing when source_type is nil or unknown" do
    assert_equal "", render(partial: "shared/source_icon", locals: { source_type: nil }).strip
    assert_equal "", render(partial: "shared/source_icon", locals: { source_type: "" }).strip
    assert_equal "", render(partial: "shared/source_icon", locals: { source_type: "bogus" }).strip
  end

  test "source_icon appends label text when label flag set" do
    output = render(partial: "shared/source_icon", locals: { source_type: "manual", label: true })
    assert_match "수기 입력", output
    output_no_label = render(partial: "shared/source_icon", locals: { source_type: "manual" })
    # aria-label always present; visible label only when flagged
    refute_match(/<span>수기 입력<\/span>/, output_no_label)
  end

  # ---------- shared/_pending_badge ----------

  test "pending_badge renders warning dot for pending_review status" do
    output = render(partial: "shared/pending_badge", locals: { status: "pending_review" })
    assert_match "text-warning", output
    assert_match "bg-warning", output
    assert_match 'aria-label="검토 대기"', output
  end

  test "pending_badge omits visible label by default" do
    output = render(partial: "shared/pending_badge", locals: { status: "pending_review" })
    refute_match(/<span>검토 대기<\/span>/, output)
  end

  test "pending_badge shows visible label when flag set" do
    output = render(partial: "shared/pending_badge", locals: { status: "pending_review", label: true })
    assert_match "<span>검토 대기</span>", output
  end

  test "pending_badge renders nothing for committed or rolled_back status" do
    assert_equal "", render(partial: "shared/pending_badge", locals: { status: "committed" }).strip
    assert_equal "", render(partial: "shared/pending_badge", locals: { status: "rolled_back" }).strip
  end

  # ---------- shared/_category_source_chip ----------

  test "category_source_chip renders category name and color dot" do
    category = categories(:food)
    output = render(partial: "shared/category_source_chip", locals: { category: category })
    assert_match category.name, output
    assert_match category.color, output
    assert_match "rounded-full", output
  end

  test "category_source_chip renders 미분류 fallback when category is nil" do
    output = render(partial: "shared/category_source_chip", locals: { category: nil })
    assert_match "미분류", output
    assert_match "text-secondary", output
  end

  test "category_source_chip omits decision mark for manual_set or nil decision" do
    category = categories(:food)
    none = render(partial: "shared/category_source_chip", locals: { category: category })
    manual = render(partial: "shared/category_source_chip", locals: { category: category, decision: :manual_set })
    assert_no_match "title=\"학습된 매핑으로 분류\"", none
    assert_no_match "title=\"학습된 매핑으로 분류\"", manual
    assert_no_match "✨", none
    assert_no_match "✨", manual
  end

  test "category_source_chip renders mapping_match dot with hover label" do
    output = render(partial: "shared/category_source_chip", locals: {
      category: categories(:food), decision: :mapping_match
    })
    assert_match 'aria-label="학습됨"', output
    assert_match "text-tertiary", output
  end

  test "category_source_chip renders keyword_match dot with hover label" do
    output = render(partial: "shared/category_source_chip", locals: {
      category: categories(:food), decision: :keyword_match
    })
    assert_match 'aria-label="키워드"', output
  end

  test "category_source_chip renders gemini_batch with ai border and sparkle" do
    output = render(partial: "shared/category_source_chip", locals: {
      category: categories(:food), decision: :gemini_batch
    })
    assert_match "✨", output
    assert_match "border-dashed", output
    assert_match "border-ai", output
    assert_match "text-ai", output
  end

  # ---------- shared/_inline_alert ----------

  test "inline_alert defaults to info tone with status role" do
    output = render(partial: "shared/inline_alert", locals: { body: "안내 본문" })
    assert_match "bg-info-subtle", output
    assert_match "text-info", output
    assert_match 'role="status"', output
    assert_match 'aria-live="polite"', output
    assert_match "안내 본문", output
  end

  test "inline_alert falls back to info when explicit tone is nil or blank" do
    [ nil, "" ].each do |blank|
      output = render(partial: "shared/inline_alert", locals: { tone: blank, body: "x" })
      assert_match "bg-info-subtle", output, "tone=#{blank.inspect} must degrade to :info"
      assert_match "text-info", output
    end
  end

  test "inline_alert tone maps to semantic utility" do
    %i[info warning positive danger ai].each do |tone|
      output = render(partial: "shared/inline_alert", locals: { tone: tone, body: "x" })
      assert_match "bg-#{tone}-subtle", output
      assert_match "text-#{tone}", output
    end
  end

  test "inline_alert danger tone escalates to alert role and assertive live region" do
    output = render(partial: "shared/inline_alert", locals: { tone: :danger, body: "위험" })
    assert_match 'role="alert"', output
    assert_match 'aria-live="assertive"', output
  end

  test "inline_alert ai tone adds border for AI channel isolation" do
    output = render(partial: "shared/inline_alert", locals: { tone: :ai, body: "AI 추천" })
    assert_match "border-ai", output
    assert_match "✨", output
  end

  test "inline_alert renders title when provided" do
    output = render(partial: "shared/inline_alert", locals: {
      tone: :info, title: "학습 제안", body: "다음부터 자동 분류"
    })
    assert_match "학습 제안", output
    assert_match "font-semibold", output
    assert_match "다음부터 자동 분류", output
  end

  test "inline_alert renders actions block beneath body" do
    output = render(inline: <<~ERB)
      <%= render "shared/inline_alert", body: "동의?" do %>
        <button class="btn-yes">예</button><button class="btn-no">아니오</button>
      <% end %>
    ERB
    assert_match "btn-yes", output
    assert_match "btn-no", output
    # actions wrapper appears after body content
    assert_match(/동의\?.*btn-yes/m, output)
  end

  test "inline_alert renders without title or body when only actions given" do
    output = render(inline: <<~ERB)
      <%= render "shared/inline_alert" do %>
        <button>확인</button>
      <% end %>
    ERB
    assert_match "확인", output
    # no title <p> nor body <p>
    refute_match(/<p[^>]*>/, output)
  end
end
