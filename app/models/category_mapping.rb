# frozen_string_literal: true

class CategoryMapping < ApplicationRecord
  belongs_to :category
  belongs_to :workspace

  SOURCES = %w[import gemini manual].freeze
  MATCH_TYPES = %w[exact contains].freeze
  # Field separator for dedup_signature. Picked a control char that cannot
  # appear inside merchant_pattern / description_pattern.
  DEDUP_SEPARATOR = "\x1F"

  before_validation :sync_dedup_signature

  validates :merchant_pattern, presence: true
  validates :dedup_signature, presence: true,
                              uniqueness: { scope: :workspace_id, message: "이미 등록된 매핑입니다" }
  validates :source, inclusion: { in: SOURCES }
  validates :match_type, inclusion: { in: MATCH_TYPES }
  validates :amount, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :category_belongs_to_workspace

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :from_import, -> { where(source: "import") }
  scope :from_gemini, -> { where(source: "gemini") }
  scope :from_manual, -> { where(source: "manual") }

  # 주어진 merchant 이름에 대한 매핑 찾기 (4단계 우선순위)
  # 1. exact + amount 일치
  # 2. exact + amount nil
  # 3. contains + amount 일치
  # 4. contains + amount nil
  def self.find_for_merchant(workspace, merchant, amount: nil)
    return nil if merchant.blank?

    scope = for_workspace(workspace)
              .where(description_pattern: [ nil, "" ])

    stripped = merchant.strip

    # 1순위: exact + amount 일치
    if amount.present?
      found = scope.find_by(merchant_pattern: stripped, match_type: "exact", amount: amount)
      return found if found
    end

    # 2순위: exact + amount nil
    found = scope.find_by(merchant_pattern: stripped, match_type: "exact", amount: nil)
    return found if found

    # 3순위: contains + amount 일치
    if amount.present?
      found = scope.where(match_type: "contains", amount: amount)
                   .to_a
                   .find { |m| stripped.downcase.include?(m.merchant_pattern.downcase) }
      return found if found
    end

    # 4순위: contains + amount nil
    scope.where(match_type: "contains", amount: nil)
         .to_a
         .find { |m| stripped.downcase.include?(m.merchant_pattern.downcase) }
  end

  # 주어진 merchant 이름에 대한 카테고리 찾기 (매핑이 있으면 반환)
  def self.find_category_for_merchant(workspace, merchant, amount: nil)
    mapping = find_for_merchant(workspace, merchant, amount: amount)
    mapping&.category
  end

  # ADR-0007 §4 explicit opt-in 학습이 만들고/조회하는 "기본 매핑" finder.
  # 기본 매핑은 (merchant_pattern, exact, description_pattern blank, amount nil).
  # description_pattern은 nil과 "" 모두 같은 dedup_signature를 가지므로 두 값을
  # 함께 본다. TransactionsController#eligible_for_learning_suggestion?와
  # CategoryLearningSuggestionsController#create가 동일하게 이 finder를 쓰도록
  # 강제한다 — 두 경로가 어긋나면 unique constraint에 의해 save가 실패할 수 있다.
  def self.find_default_exact_mapping(workspace, merchant)
    return nil if merchant.blank?

    for_workspace(workspace)
      .where(merchant_pattern: merchant.strip, match_type: "exact", amount: nil)
      .where(description_pattern: [ nil, "" ])
      .first
  end

  # 가맹점명 + 설명 조합으로 카테고리 찾기
  # 우선순위: 1. description_pattern 매칭 → 2. 기본 매핑 (description_pattern이 nil)
  def self.find_category_for_merchant_and_description(workspace, merchant, description = nil, amount: nil)
    return nil if merchant.blank?

    # 1순위: description_pattern이 있고 description이 매칭되는 경우
    if description.present?
      with_desc = for_workspace(workspace)
                    .includes(:category)
                    .where(merchant_pattern: merchant.strip)
                    .where.not(description_pattern: [ nil, "" ])
                    .to_a
                    .find { |m| description.downcase.include?(m.description_pattern.downcase) }
      return with_desc.category if with_desc
    end

    # 2순위: description_pattern이 nil인 기본 매핑
    find_category_for_merchant(workspace, merchant, amount: amount)
  end

  def match_type_label
    case match_type
    when "exact" then "정확히 일치"
    when "contains" then "포함"
    end
  end

  def source_label
    case source
    when "manual" then "수동"
    when "import" then "학습"
    when "gemini" then "AI"
    end
  end

  private

  # Keep the dedup signature in sync with the fields it derives from so the
  # `(workspace_id, dedup_signature)` unique index catches NULL-amount races
  # that SQLite's NULL-distinct unique indexes would otherwise allow.
  def sync_dedup_signature
    self.dedup_signature = [
      merchant_pattern.to_s,
      description_pattern.to_s,
      match_type.to_s,
      amount.to_s
    ].join(DEDUP_SEPARATOR)
  end

  def category_belongs_to_workspace
    if category && workspace && category.workspace_id != workspace_id
      errors.add(:category, "은(는) 같은 워크스페이스에 속해야 합니다")
    end
  end
end
