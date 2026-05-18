require "test_helper"

# Phase 6 cleanup: `.html_safe` + translation policy 잠금.
#
# Phase 6 i18n migration (#226–#231) 에서 HTML 이 필요한 translation 이 늘었다
# (`*_html` keys, link interpolation, span count interpolation 등). 현재 호출
# 패턴은 `<%= t("key", count: '<span>...</span>').html_safe %>` 처럼 호출지마다
# `.html_safe` 가 흩어져 있고, key 이름 `_html` suffix convention 도 일관되지
# 않았다 (PR #219–#231 adversarial review § P2-1).
#
# 위험은 즉시 exploit 이 아니다. 현재 interpolation 은 거의 static span /
# integer count / Rails helper output 이다. 그러나 다음 패턴이 굳어지면 XSS
# review 부담이 커지고, 향후 translation value 또는 interpolation 에 user
# input 이 섞일 때 audit 가 어렵다.
#
# 정책:
#   1. `t(...).html_safe` 호출은 *반드시* `_html` 로 끝나는 키여야 한다.
#      그래야 "이 키는 HTML 을 담는다" 는 사실이 키 이름 자체에 남는다.
#   2. body context (라벨 / span / 본문 텍스트) 에서만 `_html` 키를 사용한다.
#      attribute context (data-*, title, aria-*) 에 `_html` 키를 박지 않는다.
#      (이 테스트는 1번만 정적 검사로 잠그며, 2번은 코드리뷰 정책으로 남긴다.)
#   3. `safe_join` / `content_tag` / `link_to` 와 같은 Rails helper 의 HTML-safe
#      output 은 별도 정책 — 이 파일은 *번역 키 ↔ html_safe* 조합만 검사한다.
#
# 이 contract 가 잡는 회귀:
#   - 키 이름이 `_html` 이 아닌데 결과를 `.html_safe` 로 마킹 (현재 한 건 회귀
#     이력 — bulk_selected_count → bulk_selected_count_html 로 정정 완료).
class HtmlSafeTranslationPolicyTest < ActiveSupport::TestCase
  ROOT = Rails.root

  # `t("namespace.key")` 또는 `t(".key")` + `.html_safe` 패턴. 멀티라인 interp
  # 인자에 대비해 lazy match.
  TRANSLATE_HTML_SAFE_RE = /\bt\(\s*["']([^"']+)["'][^)]*\)\.html_safe\b/m

  # `_html` 또는 끝에 `_html()` 다른 헬퍼가 붙는 경우. translation key 만 추출
  # 했으므로 단순 suffix 비교로 충분.
  HTML_KEY_SUFFIX = "_html"

  test "every t(...).html_safe call uses an _html-suffixed key" do
    files = Dir.glob(ROOT.join("app/views/**/*.erb"))
    assert files.any?, "no ERB views found — glob mis-pointed?"

    violations = []

    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      raw = File.read(file)

      raw.scan(TRANSLATE_HTML_SAFE_RE) do
        key = Regexp.last_match(1)
        next if key.end_with?(HTML_KEY_SUFFIX)

        # lazy key form `t(".foo")` 도 동일하게 suffix 만 확인.
        offset = Regexp.last_match.begin(0)
        line = raw[0..offset].count("\n") + 1
        violations << "#{rel}:#{line} — key #{key.inspect} marked html_safe but lacks `_html` suffix"
      end
    end

    assert violations.empty?, <<~MSG
      #{violations.size} violation(s) of the i18n + html_safe policy.

      Any translation key whose result is passed through `.html_safe` MUST end
      with `_html`. This makes the HTML payload visible at the call site and
      keeps XSS audit tractable as Phase 6 expands.

      Fixes:
        - Rename the key in `config/locales/ko.yml` to add `_html`.
        - Update every reference in views.

      Violations:
      #{violations.join("\n")}
    MSG
  end
end
