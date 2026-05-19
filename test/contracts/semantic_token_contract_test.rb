require "test_helper"

# Phase 5 cleanup (Scope D): 시맨틱 토큰 계약 회귀 차단.
#
# Phase 5 (#202–#218) 가 view-only audit로 끝났을 때 helper-generated HTML,
# Stimulus가 동적으로 만드는 DOM, application.tailwind.css의 raw rgb()/hex가
# 다 빠져 있었다. 그 결과 ERB-only grep으로는 잡히지 않는 surface가 다크 모드
# 에서 깨지는 회귀가 PR #207/#214/#216/#218에서 반복적으로 발생.
#
# 이 contract test는 ADR-0008 semantic token 계약을 4 surface 전체에 강제한다:
#   - app/views/**/*.erb
#   - app/helpers/**/*.rb
#   - app/javascript/controllers/**/*.js
#   - app/assets/stylesheets/**/*.css
#
# 금지 패턴:
#   1. Tailwind palette utility (bg/text/border/ring/divide/from/to/via/stroke/fill
#      + gray/slate/zinc/neutral/stone/indigo/blue/red/green/emerald/amber/yellow/
#      purple/violet/rose/cyan/sky/teal/orange/pink/fuchsia/lime + 숫자)
#   2. truncation artifact (bg-*-subtle0 / text-*-on0 등 sed 사고 흔적)
#   3. raw hex (#RGB / #RRGGBB) / rgb(...) — allowlist 기반
#
# Allowlist는 file path 단위로 정의 (의도된 fixed-gradient hero, swatch preset 정의,
# token 정의 CSS 등).
class SemanticTokenContractTest < ActiveSupport::TestCase
  ROOT = Rails.root

  PALETTE_COLOR_NAMES = %w[
    gray slate zinc neutral stone
    indigo blue red green emerald amber yellow
    purple violet rose cyan sky teal orange pink fuchsia lime
  ].freeze

  # bg-gray-500, text-indigo-600/50, hover:bg-red-100, focus-visible:ring-indigo-500 등.
  # opacity suffix (/50 등) 도 포함.
  PALETTE_UTILITY_RE = /
    \b
    (?:(?:hover|focus|focus-visible|active|disabled|group-hover|peer-focus|dark|sm|md|lg|xl|2xl):)*
    (?:bg|text|border|ring|divide|from|to|via|stroke|fill|outline|placeholder|caret|accent|decoration|shadow)
    -
    (?:#{PALETTE_COLOR_NAMES.join("|")})
    -
    \d{2,3}
    (?:\/\d{1,3})?
    \b
  /x

  # GPT 적대적 리뷰 P1-5 (2026-05-19): black/white는 숫자 suffix가 없어서
  # PALETTE_UTILITY_RE를 우회한다. 결과적으로 `bg-black/40`, `bg-black/50`,
  # `ring-black ring-opacity-5` 같은 modal overlay·dropdown ring이 시맨틱 토큰
  # 계약 밖에서 다크 모드 회귀를 만든다. 별도 regex로 잡는다.
  #
  # Codex PR #247 P3-1: Tailwind arbitrary opacity 구문(`bg-black/[.35]`,
  # `text-white/[var(--alpha)]`)도 같은 의미축 회귀이므로 차단.
  #
  # 매칭:
  #   - bg-black, text-white, ring-black, border-white 등 (단독 utility)
  #   - bg-black/40, ring-black/5 (opacity slash suffix, digits)
  #   - bg-black/[.35], text-white/[var(--alpha)] (Tailwind arbitrary value opacity)
  #   - ring-opacity-N, divide-opacity-N (v3 legacy opacity utility — black/white 와
  #     함께 쓰이는 패턴이므로 같이 차단)
  # 매칭 제외:
  #   - PATH_ALLOWLIST의 `:all` 파일 (devise/landing/color_picker — 의도된 fixed)
  #   - 라인 단위 `semantic-allow` 마커 (match_with_allowlist 경유)
  # 코멘트 안 `/` 문자는 Ruby lexer가 regex 종결자로 잡아버려 syntax error 가 되므로
  # `#` 코멘트는 슬래시 없이 작성. 대안: %r{}x — 그러나 regex 안 grouping `()`가 많아
  # delimiter 충돌이 더 까다로움. 본 regex는 그대로 두고 코멘트만 슬래시-free 로 유지.
  BLACK_WHITE_UTILITY_RE = /
    \b
    (?:(?:hover|focus|focus-visible|active|disabled|group-hover|peer-focus|dark|sm|md|lg|xl|2xl):)*
    (?:
      (?:bg|text|border|ring|divide|from|to|via|stroke|fill|outline|placeholder|caret|accent|decoration|shadow)
      -
      (?:black|white)
      (?:
        \b                              # 단독 utility 끝 (다음 문자 non-word)
        |
        \/\d{1,3}\b                     # digit opacity suffix
        |
        \/\[[^\]\s]*\]                  # arbitrary value opacity bracket
      )
      |
      (?:ring|divide|border|bg|text)-opacity-\d{1,3}\b
    )
  /x

  # bg-action-subtle0, text-action-on0, bg-info-subtle0 등 sed truncation 흔적.
  TRUNCATION_ARTIFACT_RE = /
    \b
    (?:bg|text|border|ring|divide)
    -
    (?:action|primary|secondary|tertiary|positive|negative|warning|danger|info|ai|focus|disabled|inverse|page|surface|elev|sunken|divider|edge)
    (?:-(?:subtle|on|hover|border))?
    \d+
    \b
  /x

  # CSS context는 short hex (#abc) / 8-digit hex 모두 색이라 #RGB..#RRGGBBAA 다 잡는다.
  RAW_HEX_RE = /#\h{3,8}(?:\b|(?=[^\h]))/
  # 비-CSS source에서는 3/4-char hex가 PR reference (`#182`) 와 헷갈리므로 6/8 digit만.
  RAW_HEX_NON_CSS_RE = /(?<![\w])#(?:\h{8}|\h{6})(?![\w])/

  # rgb(...), rgba(...).
  RAW_RGB_RE = /\brgba?\s*\(/

  # Codex PR #224 P2 fallback: 토큰화 불가능한 line은 `semantic-allow` 마커로 면제.
  # 예: chart_tabs_controller.js의 `_resolveCssVar` fallback hex.
  ALLOW_LINE_MARKER = "semantic-allow"

  # 파일 경로별 allowlist. :all 이면 전체 파일 통과, :token_definitions 면 token 영역
  # (@theme { ... }) 를 stripping 후 검사. 정확한 이유를 코멘트에 명시.
  PATH_ALLOWLIST = {
    # 전체 페이지가 fixed gradient hero (theme 안 따라감) — PR #213 P1 결정.
    "app/views/pages/landing.html.erb" => :all,
    "app/views/devise/sessions/new.html.erb" => :all,
    "app/views/devise/registrations/new.html.erb" => :all,
    "app/views/devise/passwords/new.html.erb" => :all,

    # Category color swatch preset (사용자 정의 카테고리 hex) — 의도된 raw hex.
    "app/views/shared/_color_picker.html.erb" => :all,

    # 임의 swatch 색 위의 contrast icon은 페이지 테마가 아니라 swatch 색에 대한
    # contrast 계산이라 raw hex 필수 (Phase 5 cleanup C-3 #223에서 결정).
    "app/javascript/controllers/color_picker_controller.js" => :all,

    # ADR-0008 semantic token 정의 자체가 light-dark()로 raw hex를 갖는다.
    "app/assets/stylesheets/application.tailwind.css" => :token_definitions
  }.freeze

  # Codex PR #224 P2 fix: token-definition stripping은 `@theme { ... }` 블록 안의
  # 정의에만 적용. 다른 layer/scope에 `--foo: #hex;`를 박으면 그건 토큰이 아니므로
  # raw hex로 잡혀야 한다.
  def strip_theme_block(css_body)
    # @theme { ... } 블록을 통째로 제거. CSS @theme 블록은 nested {} 없이 single level
    # custom property 선언이므로 non-greedy match로 충분.
    css_body.gsub(/@theme\s*\{[^}]*\}/m, "")
  end

  def assert_no_palette_in_css(file, rel_path)
    body = File.read(file)
    # application.tailwind.css 만 @theme 블록을 stripping. 다른 stylesheet는 stripping
    # 없이 전체 검사 (Codex PR #224 P2).
    stripped = (PATH_ALLOWLIST[rel_path] == :token_definitions) ? strip_theme_block(body) : body
    # /* ... */ 코멘트 제거 (의도 설명에 토큰 이름이 들어갈 수 있음).
    stripped = stripped.gsub(%r{/\*.*?\*/}m, "")
    assert_no_match PALETTE_UTILITY_RE, stripped,
                    "#{rel_path}: palette utility class found in CSS"
    assert_no_match TRUNCATION_ARTIFACT_RE, stripped,
                    "#{rel_path}: truncation artifact (bg-*-subtle0 등) found in CSS"
    # Codex PR #247 P2-2: BW guard는 ERB/helper/JS surface 만이 아니라 CSS
    # surface(`@apply bg-black/50`, `ring-opacity-*`)에서도 동일하게 적용.
    # 그렇지 않으면 documented surface 중 한 곳(stylesheets)에 blind spot이 남는다.
    assert_no_match BLACK_WHITE_UTILITY_RE, stripped,
                    "#{rel_path}: raw black/white utility (bg-black/text-white/ring-black/ring-opacity-*) found in CSS — use bg-overlay / ring-divider / text-action-on / bg-surface 시맨틱 토큰"
    # raw hex / rgb()는 token 정의 외에서는 의미 손실 — keyframes/utilities에서는
    # var(--color-*) + color-mix() 로만 가능.
    assert_no_match RAW_HEX_RE, stripped,
                    "#{rel_path}: raw hex found outside token definitions"
    assert_no_match RAW_RGB_RE, stripped,
                    "#{rel_path}: raw rgb() found outside token definitions"
  end

  # 코멘트 라인을 무시하기 위한 마스킹. ERB/JS/Ruby/CSS 코멘트 형식을 처리.
  # Phase 5 cleanup 코멘트에 토큰 이름이 들어있어도 contract test가 통과해야 함.
  def strip_comments(content, extension)
    case extension
    when ".erb", ".html", ".html.erb"
      # ERB 코멘트 + HTML 코멘트
      content.gsub(/<%#.*?%>/m, "").gsub(/<!--.*?-->/m, "")
    when ".js"
      # // ... 단일 라인 + /* ... */ 블록 — string literal 안의 내용은 거짓 양성 가능,
      # 그러나 본 contract는 본문 클래스 추출용이라 안전한 쪽으로 코멘트 제거.
      content.gsub(/\/\/.*$/, "").gsub(%r{/\*.*?\*/}m, "")
    when ".rb"
      # Codex PR #224 P2: 라인 시작 `#` 만 제거. `"#{interpolation}"` 안 `#`을
      # 보호하기 위해서. inline `# comment`는 보존되지만 contract test 본문 검사
      # 목적상 거짓 음성보다는 false positive 가능성을 받아들이는 게 안전.
      content.gsub(/^\s*#.*$/, "")
    when ".css"
      content.gsub(%r{/\*.*?\*/}m, "")
    else
      content
    end
  end

  def line_for_offset(text, offset)
    text[0..offset].count("\n") + 1
  end

  def assert_no_forbidden_patterns(file, rel_path)
    raw = File.read(file)
    ext = File.extname(file)
    stripped = strip_comments(raw, ext)

    allowlist = PATH_ALLOWLIST[rel_path]
    return if allowlist == :all
    return if allowlist == :token_definitions # CSS는 별도 메서드에서 처리

    # palette utility
    if (m = stripped.match(PALETTE_UTILITY_RE))
      line = line_for_offset(stripped, m.begin(0))
      flunk(<<~MSG)
        #{rel_path}:#{line} — palette utility "#{m[0]}" found.
        Use ADR-0008 semantic tokens instead:
          - text-gray-* → text-primary/secondary/tertiary/disabled
          - bg-gray-* → bg-elev/sunken/page/surface
          - text-indigo-*/bg-indigo-* → text-action/bg-action(-subtle)
          - text-red-*/bg-red-* → text-danger/bg-danger-subtle
          - text-green-*/bg-green-* → text-positive/bg-positive-subtle
          - text-yellow-*/text-amber-* → text-warning/bg-warning-subtle
          - text-blue-* → text-info/bg-info-subtle
          - text-violet-*/text-purple-* → text-ai/text-category-7
        See `app/assets/stylesheets/application.tailwind.css` for full token list.
      MSG
    end

    # black/white utility (GPT 적대적 리뷰 P1-5 blind spot 보강)
    # Codex PR #247 P2-1: flunk 메시지가 `semantic-allow` 마커를 광고하므로
    # 실제 매칭도 라인 단위 allowlist를 존중해야 한다 (raw hex/rgb 와 동일).
    if (m = match_with_allowlist(stripped, BLACK_WHITE_UTILITY_RE, raw))
      line = line_for_offset(stripped, m.begin(0))
      flunk(<<~MSG)
        #{rel_path}:#{line} — raw black/white utility "#{m[0]}" found.
        ADR-0008 semantic token 계약을 우회한다 (modal overlay·dropdown ring 회귀 원인).
        교체 예시:
          - bg-black/40, bg-black/50 (modal backdrop) → bg-overlay
          - ring-1 ring-black ring-opacity-5 (dropdown ring) → ring-1 ring-divider
          - bg-black/[.35], text-white/[var(--alpha)] (arbitrary opacity) → 시맨틱 token
          - text-white on bg-action 등 → text-action-on
          - bg-white card → bg-surface
        의도된 고정색이 필요한 페이지(landing/devise/color_picker)는 PATH_ALLOWLIST = :all.
        라인 단위 면제가 필요하면 `#{ALLOW_LINE_MARKER}` 코멘트 마커를 같은 라인에 추가.
      MSG
    end

    # truncation
    if (m = stripped.match(TRUNCATION_ARTIFACT_RE))
      line = line_for_offset(stripped, m.begin(0))
      flunk(<<~MSG)
        #{rel_path}:#{line} — truncation artifact "#{m[0]}" found.
        Looks like a sed substitution accidentally chopped a digit suffix
        (e.g. bg-blue-500 → bg-info-subtle0 when applying `bg-blue-50 → bg-info-subtle`
        without a word boundary). Fix the truncated class to the intended token.
      MSG
    end

    # Codex PR #224 P2: raw hex / rgb()도 비-CSS surface에서 검사. inline style 이나
    # JS-generated string으로 raw color가 들어가는 케이스 차단. 임의 swatch 색 위
    # contrast icon처럼 토큰으로 표현 불가능한 도메인 케이스는 path allowlist (:all)
    # 또는 line-level `semantic-allow` 마커.
    # 비-CSS는 PR reference (#123) 와 구분 위해 6/8 hex digit만.
    if (m = match_with_allowlist(stripped, RAW_HEX_NON_CSS_RE, raw))
      line = line_for_offset(stripped, m.begin(0))
      flunk(<<~MSG)
        #{rel_path}:#{line} — raw hex literal "#{m[0]}" found.
        Use ADR-0008 semantic CSS var (var(--color-*)) or a tone className.
        If this is a theme-independent contrast value (e.g. icon on arbitrary
        user-chosen swatch), add the file to PATH_ALLOWLIST with :all,
        or add an inline `#{ALLOW_LINE_MARKER}` comment on the offending line.
      MSG
    end
    if (m = match_with_allowlist(stripped, RAW_RGB_RE, raw))
      line = line_for_offset(stripped, m.begin(0))
      flunk(<<~MSG)
        #{rel_path}:#{line} — raw rgb() literal found.
        Same rule as raw hex: use var(--color-*), path allowlist, or
        `#{ALLOW_LINE_MARKER}` inline marker.
      MSG
    end
  end

  # 라인 단위 allowlist 마커 확인. stripped에서 패턴이 잡히더라도 같은 라인의
  # raw 원본에 `semantic-allow` 마커가 있으면 무시한다.
  def match_with_allowlist(stripped, regex, raw)
    offset = 0
    raw_lines = raw.lines
    while (m = stripped.match(regex, offset))
      line = line_for_offset(stripped, m.begin(0))
      raw_line = raw_lines[line - 1] || ""
      return m unless raw_line.include?(ALLOW_LINE_MARKER)
      offset = m.end(0)
    end
    nil
  end

  test "ERB views use semantic tokens (no palette utility / no truncation artifact)" do
    files = Dir.glob(ROOT.join("app/views/**/*.erb"))
    assert files.any?, "no ERB views found — glob mis-pointed?"
    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      assert_no_forbidden_patterns(file, rel)
    end
  end

  test "helpers generate semantic-token HTML" do
    files = Dir.glob(ROOT.join("app/helpers/**/*.rb"))
    assert files.any?, "no helpers found — glob mis-pointed?"
    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      assert_no_forbidden_patterns(file, rel)
    end
  end

  test "Stimulus controllers' dynamic DOM uses semantic tokens (no palette / no ${color} template literal)" do
    files = Dir.glob(ROOT.join("app/javascript/controllers/**/*.js"))
    assert files.any?, "no Stimulus controllers found — glob mis-pointed?"
    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      assert_no_forbidden_patterns(file, rel)

      # 동적 ${color} template literal로 만든 Tailwind class도 차단.
      # 예: `bg-${color}-50`, `text-${color}-600`.
      raw = File.read(file)
      stripped = strip_comments(raw, ".js")
      if stripped.match?(/(?:bg|text|border|ring)-\$\{[^}]+\}-/)
        flunk(<<~MSG)
          #{rel} — dynamic Tailwind class via template literal `${color}` found.
          Tailwind JIT does not reliably scan runtime concatenations, and the
          pattern bypasses the ADR-0008 semantic contract. Use a static
          tone map instead (e.g. `STAT_TONES = { deleted: "bg-danger-subtle", ... }`).
        MSG
      end
    end
  end

  test "all stylesheets use only semantic var(--color-*) outside token definitions" do
    # Codex PR #224 P2 + P3: 전체 stylesheets 검사 + canonical 파일 누락 시 loud fail.
    files = Dir.glob(ROOT.join("app/assets/stylesheets/**/*.css"))
    assert files.any?, "no stylesheets found — glob mis-pointed?"

    canonical = ROOT.join("app/assets/stylesheets/application.tailwind.css")
    assert File.exist?(canonical),
           "canonical stylesheet application.tailwind.css missing — contract test must not silently pass on path drift"

    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      assert_no_palette_in_css(file, rel)
    end
  end

  test "no truncation artifact across all four surfaces" do
    # Belt-and-suspenders: 위 테스트들이 surface별로 truncation을 보지만,
    # 단일 sentinel로도 한번 더 확인.
    files = []
    files.concat Dir.glob(ROOT.join("app/views/**/*.erb"))
    files.concat Dir.glob(ROOT.join("app/helpers/**/*.rb"))
    files.concat Dir.glob(ROOT.join("app/javascript/controllers/**/*.js"))
    files.concat Dir.glob(ROOT.join("app/assets/stylesheets/**/*.css"))
    assert files.any?, "no source files collected — globs mis-pointed?"

    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      ext = File.extname(file)
      stripped = strip_comments(File.read(file), ext)
      if (m = stripped.match(TRUNCATION_ARTIFACT_RE))
        line = line_for_offset(stripped, m.begin(0))
        flunk("#{rel}:#{line} — truncation artifact `#{m[0]}`")
      end
    end
  end
end
