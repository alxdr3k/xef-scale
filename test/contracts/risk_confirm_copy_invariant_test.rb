require "test_helper"

# Phase 6 cleanup: 위험 행동 confirm 카피 invariant.
#
# Phase 6 i18n migration 으로 destructive/irreversible action 의 confirm 카피가
# 모두 `config/locales/ko.yml` 단일 출처로 옮겨졌다 (#228, #229, #231 등). 이는
# 좋은 변화지만, 위험 카피가 이제 YAML 한 줄 수정만으로 약해질 수 있다는 새
# 회귀 표면을 만든다.
#
# 본 invariant test 는 destructive action confirm 키에 대해 "최소한 무엇이
# 일어나는지/되돌릴 수 없다는 사실/영향 범위" 가 텍스트에 남아 있는지 확인한다.
# 정확한 문구가 아니라 *위험 정보의 존재* 를 잠근다.
#
# 카테고리:
#   - irreversible_action:  되돌릴 수 없 / 영구 / 비가역
#   - bulk_action:          전체 / 모두 / 일괄
#   - amount_impact:        총액 / 장부 / 교체 / 숨김 / 반영
#   - scope_label:          이름/카운트/대상 같은 영향 범위 변수
#
# 새 destructive 키가 추가되면 RISK_KEYS 에 등록한다. 이 등록 자체가 "위험
# 카피라는 사실" 을 코드 수준에 남기는 역할이다.
class RiskConfirmCopyInvariantTest < ActiveSupport::TestCase
  PATTERNS = {
    irreversible: /되돌릴 수 없|영구|비가역/,
    bulk:         /전체|모두|모든|일괄/,
    amount:       /총액|장부|교체|숨기|반영되지/,
    scope:        /%\{[a-z_]+\}/   # name/count interpolation
  }.freeze

  # destructive 키 등록부. 각 항목은 다음 형태:
  #   [I18n key, [필수 PATTERN 카테고리 …]]
  #
  # 누락이 일어나면 fail. 새 destructive action 을 추가하면 반드시 이 목록을
  # 함께 갱신한다.
  RISK_KEYS = [
    # reviews 화면 cancel/rollback — review 워크플로 전체 폐기. 비가역 + 일괄.
    [ "reviews.show.cancel_all_confirm",                  %i[irreversible bulk] ],
    [ "reviews.show.rollback_confirm",                    %i[irreversible bulk] ],

    # parsing_session delete — 비가역.
    [ "parsing_sessions.actions.delete_confirm",          %i[irreversible] ],

    # reviews duplicate bulk — 장부 총액/숨김/교체 임팩트.
    [ "reviews.duplicate_section.bulk_keep_original_confirm", %i[bulk amount] ],
    [ "reviews.duplicate_section.bulk_keep_new_confirm",      %i[bulk amount] ],
    [ "reviews.duplicate_section.bulk_keep_both_confirm",     %i[bulk amount] ],

    # workspaces 설정 페이지 삭제 — 비가역 + 이름 스코프.
    [ "workspaces.settings.delete_confirm",               %i[irreversible scope] ],

    # workspace_more 워크스페이스 삭제 — 범위 명시 (모든 거래·카테고리·매핑·세션).
    [ "workspace_more.delete_confirm",                    %i[bulk] ]
  ].freeze

  test "every registered destructive confirm key has the required risk markers" do
    missing = []

    RISK_KEYS.each do |key, required_categories|
      translated = I18n.t(key, default: nil)
      if translated.nil?
        missing << "#{key}: not found in locale"
        next
      end

      required_categories.each do |category|
        pattern = PATTERNS.fetch(category)
        next if translated.match?(pattern)
        missing << <<~MSG
          #{key}: missing #{category} marker (#{pattern.source})
            value: #{translated.inspect}
        MSG
      end
    end

    assert missing.empty?, <<~MSG
      #{missing.size} risk-copy invariant violation(s).

      A destructive/irreversible action's confirm text was weakened — the
      required risk marker(s) disappeared. Restore the original copy, or if
      the change is intentional, update RISK_KEYS / PATTERNS together with
      the product decision documented in the PR description.

      #{missing.join("\n")}
    MSG
  end

  test "every *_confirm key in ko.yml is registered as risk copy or explicitly excluded" do
    # Walk the loaded ko backend and find every *_confirm key, then assert
    # it's either in RISK_KEYS or in EXCLUDED_KEYS. This way new destructive
    # copy can't slip past the invariant registry.
    confirm_keys = collect_confirm_keys(I18n.backend.send(:translations).fetch(:ko))
    known_keys = (RISK_KEYS.map(&:first) + EXCLUDED_KEYS).to_set

    unregistered = confirm_keys.reject { |k| known_keys.include?(k) }

    assert unregistered.empty?, <<~MSG
      #{unregistered.size} *_confirm key(s) are present in ko.yml but not
      registered. Either add them to RISK_KEYS with the required risk
      markers, or list them under EXCLUDED_KEYS with a one-line rationale
      (e.g. "low-risk: single-row delete").

      #{unregistered.sort.join("\n")}
    MSG
  end

  # 낮은 위험으로 invariant 검사가 과한 키. 추가할 때는 한 줄짜리 이유 코멘트.
  EXCLUDED_KEYS = [
    "categories.row.delete_confirm",                # single category delete — UI 단의 generic confirm
    "category_mappings.row.delete_confirm",         # single mapping rule delete — 낮은 위험
    "transactions.row.delete_confirm",              # single transaction delete — UI 단의 generic confirm
    "reviews.import_issues.dismiss_confirm",        # single import issue dismiss — 낮은 위험
    "workspace_memberships.index.remove_confirm",   # single member remove (workspace_more page)
    "workspace_invitations.index.delete_confirm",   # single invitation remove — 낮은 위험
    "workspaces.settings.remove_confirm"            # settings 페이지 단일 멤버 제거
  ].freeze

  private

  def collect_confirm_keys(translations, prefix = nil)
    result = []
    translations.each do |key, value|
      full = [ prefix, key ].compact.join(".")
      if value.is_a?(Hash)
        result.concat(collect_confirm_keys(value, full))
      elsif key.to_s.end_with?("_confirm")
        result << full
      end
    end
    result
  end
end
