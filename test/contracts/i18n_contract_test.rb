require "test_helper"

# Phase 6 i18n contract: hardcoded 한글 문자열이 view 파일에 다시 들어오는 것을 차단.
#
# Phase 6 (#225–#234) 가 ui-redesign-plan §6 카피·i18n 마이그레이션을 완료하면서
# `t("...")` 호출로 일관화한 후, 새 PR이 무심코 한글을 다시 view에 박아넣는 회귀를
# 막기 위해 정적 검사를 한다.
#
# 검사 대상:
#   - app/views/**/*.erb
#
# 허용:
#   1. ERB 코멘트 (<%# ... %>) — 한글 docstring/decision note 자유.
#   2. HTML 코멘트 (<!-- ... -->) — 같은 이유.
#   3. allowlist (path 단위) — 의도된 한글 hardcoded 케이스.
#   4. `t("...")` 호출이 같은 라인에 있는 경우는 키 안의 한글로 간주 — 통과.
#
# 금지:
#   - 본문 텍스트로 노출되는 한글
#   - HTML attribute (placeholder, title, aria-label, alt) 의 한글
class I18nContractTest < ActiveSupport::TestCase
  ROOT = Rails.root

  # ERB/HTML 코멘트를 제거. 코멘트 안 한글은 자유.
  def strip_comments(content)
    content
      .gsub(/<%#.*?%>/m, "")
      .gsub(/<!--.*?-->/m, "")
      # ERB <% ... %> 안 Ruby line comment (`# ...`) 도 strip — 라인 시작 `#` 만.
      # `"#{interpolation}"` 의 `#` 은 line-start 가 아니므로 보호된다.
      .gsub(/^(\s*)#.*$/, "\\1")
  end

  # 파일 경로별 allowlist. 단순 한글 문자열이 view에 들어가야 하는 의도된 케이스.
  # 추가 시 *반드시* 이유 코멘트와 함께.
  PATH_ALLOWLIST = [
    # 비로그인 랜딩 페이지 — 마케팅 카피로 i18n 추출 가치가 낮고 현재 한국어 단일 앱.
    # 향후 영어 지원 시 별도 슬라이스로 처리.
    "app/views/pages/landing.html.erb",
    # ERB docstring 내부에 ERB escape (`<%% end %>`)가 있어 `<%# ... %>` 매치가 일찍
    # 끊긴다. partial 본문은 한글 0줄, docstring만 한글이라 path-level allowlist.
    "app/views/shared/_context_header.html.erb"
  ].freeze

  # 라인 단위 inline allowlist 마커. 의도된 hardcoded 한글 (모델 enum 값 비교 등)
  # 이 있는 라인에 `i18n-allow` 코멘트 마커가 있으면 skip.
  ALLOW_LINE_MARKER = "i18n-allow"

  # 한글 한 글자라도 등장하면 매치. 코멘트 stripping이 필수.
  HANGUL_RE = /[\u{AC00}-\u{D7A3}\u{1100}-\u{11FF}\u{3130}-\u{318F}]/

  test "no hardcoded Hangul in ERB views (use t() instead)" do
    files = Dir.glob(ROOT.join("app/views/**/*.erb"))
    assert files.any?, "no ERB views found — glob mis-pointed?"

    violations = []
    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      next if PATH_ALLOWLIST.include?(rel)

      raw_lines = File.read(file).lines
      stripped = strip_comments(File.read(file))
      stripped.each_line.with_index(1) do |line, lineno|
        next unless line.match?(HANGUL_RE)
        # inline allowlist marker
        raw_line = raw_lines[lineno - 1] || ""
        next if raw_line.include?(ALLOW_LINE_MARKER)
        # t("key.path") / I18n.t("key.path") 호출은 마스킹 — 인자 자체 한글이
        # 아니라 키 path에 한글이 있을 가능성도 0이므로 그대로 두면 false positive.
        masked = line.dup
        masked.gsub!(/\bt\(\s*["'][^"']*["']/, "T_CALL")
        masked.gsub!(/\bI18n\.t\(\s*["'][^"']*["']/, "T_CALL")
        next unless masked.match?(HANGUL_RE)
        violations << "#{rel}:#{lineno} — #{line.strip[0, 120]}"
      end
    end

    if violations.any?
      flunk(<<~MSG)
        #{violations.size} hardcoded Hangul violation(s) in ERB views.
        Phase 6 (ui-redesign-plan §6) migrated all user-facing copy to ko.yml
        via t() helper. Replace inline 한글 with t("namespace.key").

        First 30 violations:
        #{violations.first(30).join("\n")}

        See `config/locales/ko.yml` for existing keys. If a string is
        intentionally hardcoded (e.g. landing page marketing copy),
        add the file path to `PATH_ALLOWLIST` with a reason comment.
      MSG
    end
  end
end
