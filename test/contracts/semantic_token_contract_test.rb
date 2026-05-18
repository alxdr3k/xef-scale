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

  # #RGB / #RGBA / #RRGGBB / #RRGGBBAA — 코멘트와 allowlist는 따로 처리.
  RAW_HEX_RE = /#\h{3,8}(?:\b|(?=[^\h]))/

  # rgb(...), rgba(...).
  RAW_RGB_RE = /\brgba?\s*\(/

  # 파일 경로별 allowlist. nil이면 전체 파일 통과, Array면 그 줄들은 무시 (1-indexed).
  # 정확한 이유를 명시해서 추후 audit에서 의도가 보이도록 한다.
  PATH_ALLOWLIST = {
    # 전체 페이지가 fixed gradient hero (theme 안 따라감) — PR #213 P1 결정.
    "app/views/pages/landing.html.erb" => :all,
    "app/views/devise/sessions/new.html.erb" => :all,
    "app/views/devise/registrations/new.html.erb" => :all,
    "app/views/devise/passwords/new.html.erb" => :all,

    # Category color swatch preset (사용자 정의 카테고리 hex) — 의도된 raw hex.
    "app/views/shared/_color_picker.html.erb" => :all,

    # ADR-0008 semantic token 정의 자체가 light-dark()로 raw hex를 갖는다.
    "app/assets/stylesheets/application.tailwind.css" => :token_definitions
  }.freeze

  # application.tailwind.css 안에서 token 정의 영역 (--color-*: light-dark(...)) 외의
  # 부분만 검사. token 정의는 raw hex가 의도된 곳.
  def assert_no_palette_in_css(file)
    body = File.read(file)
    # @theme 블록 안의 모든 -- 토큰 정의 (color/shadow/radius/transition/font 등)는
    # raw hex/rgba()가 의도된 위치. line 단위로 제거.
    stripped = body.gsub(/^\s*--[\w-]+:\s*[^;]*;.*$/, "")
    # /* ... */ 코멘트도 제거 (의도 설명에 토큰 이름이 들어갈 수 있음).
    stripped = stripped.gsub(%r{/\*.*?\*/}m, "")
    assert_no_match PALETTE_UTILITY_RE, stripped,
                    "#{file}: palette utility class found in CSS"
    assert_no_match TRUNCATION_ARTIFACT_RE, stripped,
                    "#{file}: truncation artifact (bg-*-subtle0 등) found in CSS"
    # raw hex / rgb()는 token 정의 외에서는 의미 손실 — keyframes/utilities에서는
    # var(--color-*) + color-mix() 로만 가능.
    assert_no_match RAW_HEX_RE, stripped,
                    "#{file}: raw hex found outside token definitions"
    assert_no_match RAW_RGB_RE, stripped,
                    "#{file}: raw rgb() found outside token definitions"
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
      # # ... 단일 라인 (string literal 안의 #도 제거되지만 본 contract는 본문 클래스 추출 목적)
      content.gsub(/#.*$/, "")
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

  test "application.tailwind.css uses only semantic var(--color-*) outside token definitions" do
    file = ROOT.join("app/assets/stylesheets/application.tailwind.css")
    assert_no_palette_in_css(file) if File.exist?(file)
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
