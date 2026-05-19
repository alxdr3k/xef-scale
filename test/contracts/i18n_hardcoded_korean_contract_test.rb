require "test_helper"

# Phase 6 cleanup: i18n hardcoded Korean 계약 회귀 차단.
#
# Phase 6 (#225–#231 등) 의 view i18n migration이 "잔여 한글 0건" 을 수동 grep
# 으로만 주장했다. 이전 Phase 5에서 같은 패턴이 깨졌듯 (view-only audit으로는
# helper/JS-built DOM/controller flash 가 빠짐), Phase 6도 contract test 없이는
# 다음 PR에서 쉽게 회귀한다.
#
# 이 contract test는 다음 surface에서 사용자 가시 한글 리터럴(한글 음절 블록
# U+AC00–U+D7AF)을 차단한다:
#   - app/views/**/*.erb
#   - app/helpers/**/*.rb
#   - app/javascript/controllers/**/*.js
#   - app/controllers/**/*.rb
#   - app/mailers/**/*.rb
#   - app/jobs/**/*.rb (사용자 가시 flash/메시지에 한해)
#
# 정책:
#   - 새 파일을 추가하면서 한글 리터럴을 박으면 fail.
#   - 이미 한글이 있는 파일은 BASELINE_FILES_WITH_KOREAN 에 등록. 점진 migration
#     예정. 이 목록의 파일이 한글을 제거하면 baseline에서 같이 빼야 한다.
#   - 파일 단위 baseline은 한 줄짜리 한글 추가도 막지 못한다는 한계가 있다.
#     그러나 신규 surface에 한글이 새어나가는 가장 큰 회귀 통로는 막는다.
#     라인 단위 면제는 `i18n-allow` inline 마커로 지정.
#   - 코멘트(ERB `<%# %>`, JS `//`, Ruby 라인 시작 `#`, CSS `/* */`) 는 무시.
#
# 향후 강화 방향:
#   - baseline 파일이 0이 되면 BASELINE_FILES_WITH_KOREAN 자체를 제거하고
#     전체 strict 모드로 전환.
#   - 라인-카운트 baseline (per-file 회귀만 차단) 으로 점진 축소.
class I18nHardcodedKoreanContractTest < ActiveSupport::TestCase
  ROOT = Rails.root

  # 한글 음절 블록만 검사. Hangul jamo (U+1100–U+11FF) 와 호환 자모
  # (U+3130–U+318F) 는 보통 단독 사용되지 않으므로 제외.
  KOREAN_RE = /\p{Hangul}/

  # 라인 단위 면제 마커.
  ALLOW_LINE_MARKER = "i18n-allow"

  # 한글 리터럴이 현재 남아있어 점진 migration 대상인 파일. 새 파일이 이 목록에
  # 없으면서 한글을 포함하면 contract fail.
  #
  # 이 목록을 줄이는 것이 Phase 6 잔여 작업이다. 줄이려면:
  #   1) 해당 파일의 한글을 `I18n.t(...)` / data-* attr / locale yml 로 옮긴다.
  #   2) 이 목록에서 파일을 제거한다.
  #   3) 테스트 재실행으로 회귀 차단이 새 surface까지 확장됐는지 확인.
  BASELINE_FILES_WITH_KOREAN = %w[
    app/views/pages/landing.html.erb
    app/views/shared/_context_header.html.erb
  ].freeze

  SURFACES = [
    { glob: "app/views/**/*.erb",                     ext: ".erb" },
    { glob: "app/helpers/**/*.rb",                    ext: ".rb"  },
    { glob: "app/javascript/controllers/**/*.js",     ext: ".js"  },
    { glob: "app/controllers/**/*.rb",                ext: ".rb"  },
    { glob: "app/mailers/**/*.rb",                    ext: ".rb"  },
    { glob: "app/jobs/**/*.rb",                       ext: ".rb"  }
  ].freeze

  # 코멘트 마스킹. semantic_token_contract_test 와 동일한 정책:
  # 한글이 코멘트에만 있으면 contract 통과.
  #
  # 라인 시작 들여쓰기 매치에 `\s*` 대신 `[ \t]*`를 쓴다. Ruby 정규식의 `\s`는
  # `\n`도 포함하므로 `^\s*#` 가 직전 빈 줄의 newline까지 먹어버려 raw vs stripped
  # 사이에 라인 정렬이 어긋나고 (`first_disallowed_match`가 잘못된 raw 라인을
  # 검사해 i18n-allow 마커를 놓치는 회귀 원인), `.lines.count`도 줄어든다.
  def strip_comments(content, ext)
    case ext
    when ".erb"
      # ERB 코멘트 + HTML 코멘트 + ERB 스크립트릿(`<% ... %>`) 내부의 Ruby 라인
      # 코멘트까지 제거. partial 안 Ruby 코멘트가 user-visible 한글로 잘못 잡히는
      # false positive(예: `_variance_card.html.erb`의 ADR 주석)를 차단한다.
      content
        .gsub(/<%#.*?%>/m, "")
        .gsub(/<!--.*?-->/m, "")
        .gsub(/<%[-=]?.*?%>/m) { |scriptlet| scriptlet.gsub(/^[ \t]*#.*$/, "") }
    when ".js"
      content.gsub(/\/\/.*$/, "").gsub(%r{/\*.*?\*/}m, "")
    when ".rb"
      # 라인 시작 `#` 만 제거. `"#{interpolation}"` 안의 `#` 보호.
      content.gsub(/^[ \t]*#.*$/, "")
    else
      content
    end
  end

  # 라인 단위 면제 마커가 들어간 라인을 raw에서 함께 비운다. stale baseline 검사가
  # `i18n-allow`로 허용된 한 줄짜리 enum 비교 같은 잔여물을 "아직 한글 있음"으로
  # 오인하지 않도록 한다.
  def apply_allow_marker(raw, stripped)
    return stripped unless raw.include?(ALLOW_LINE_MARKER)
    raw_lines = raw.lines
    stripped_lines = stripped.lines
    stripped_lines.each_with_index.map do |line, i|
      raw_line = raw_lines[i] || ""
      raw_line.include?(ALLOW_LINE_MARKER) ? line.gsub(KOREAN_RE, "") : line
    end.join
  end

  def line_for_offset(text, offset)
    text[0..offset].count("\n") + 1
  end

  # 라인-마커 면제 적용. stripped 에서 매치된 라인의 raw 원본에 `i18n-allow` 가
  # 있으면 통과.
  def first_disallowed_match(raw, stripped)
    raw_lines = raw.lines
    offset = 0
    while (m = stripped.match(KOREAN_RE, offset))
      line = line_for_offset(stripped, m.begin(0))
      raw_line = raw_lines[line - 1] || ""
      return [ m, line ] unless raw_line.include?(ALLOW_LINE_MARKER)
      offset = m.end(0)
    end
    nil
  end

  test "no new Korean literals outside baseline files" do
    files = SURFACES.flat_map { |s| Dir.glob(ROOT.join(s[:glob])) }
    assert files.any?, "no source files collected — globs mis-pointed?"

    baseline_set = BASELINE_FILES_WITH_KOREAN.to_set
    violations = []

    files.each do |file|
      rel = Pathname.new(file).relative_path_from(ROOT).to_s
      next if baseline_set.include?(rel)

      raw = File.read(file)
      ext = File.extname(file)
      stripped = strip_comments(raw, ext)

      result = first_disallowed_match(raw, stripped)
      next unless result

      m, line = result
      snippet = (raw.lines[line - 1] || "").strip
      violations << <<~MSG
        #{rel}:#{line} — hardcoded Korean literal "#{m[0]}" found.
        Line: #{snippet.length > 120 ? snippet[0..117] + "..." : snippet}
      MSG
    end

    assert violations.empty?, <<~MSG
      #{violations.size} file(s) outside Phase 6 baseline contain hardcoded Korean.

      #{violations.join("\n")}

      Fix options:
        1. Move the string to `config/locales/ko.yml` and use `I18n.t(...)` / `t(".key")`.
        2. For JS controllers, inject the string via Stimulus value (data-* attr) from
           the view side using `t(...)`.
        3. If the Korean literal is intentional (single-use, e.g. a fixture/test seed
           or a comment-equivalent), add an inline `#{ALLOW_LINE_MARKER}` marker on the
           same line.
        4. If the file should be tracked for incremental migration (i.e. already has
           many Korean literals), add its relative path to BASELINE_FILES_WITH_KOREAN
           in this test. Note: this expands the migration surface — prefer (1) when
           feasible.
    MSG
  end

  test "baseline files still exist (stale entries get removed)" do
    # baseline 항목이 더 이상 존재하지 않거나 한글이 모두 사라졌으면 baseline 에서
    # 빼라고 알려준다. 그래야 contract surface 가 자연스럽게 좁아진다.
    stale = []
    BASELINE_FILES_WITH_KOREAN.each do |rel|
      full = ROOT.join(rel)
      unless File.exist?(full)
        stale << "#{rel} — file no longer exists"
        next
      end
      raw = File.read(full)
      ext = File.extname(full)
      stripped = apply_allow_marker(raw, strip_comments(raw, ext))
      unless stripped.match?(KOREAN_RE)
        stale << "#{rel} — no Korean literals left (after comment/i18n-allow masking), baseline entry obsolete"
      end
    end

    assert stale.empty?, <<~MSG
      #{stale.size} baseline entry/entries are stale. Remove from
      BASELINE_FILES_WITH_KOREAN so the strict surface expands:

      #{stale.join("\n")}
    MSG
  end
end
