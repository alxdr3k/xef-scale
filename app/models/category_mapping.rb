# frozen_string_literal: true

class CategoryMapping < ApplicationRecord
  belongs_to :category
  belongs_to :workspace

  SOURCES = %w[import gemini manual].freeze

  validates :merchant_pattern, presence: true
  validates :merchant_pattern, uniqueness: {
    scope: [ :workspace_id, :description_pattern ],
    message: "이미 등록된 매핑입니다"
  }
  validates :source, inclusion: { in: SOURCES }

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :from_import, -> { where(source: "import") }
  scope :from_gemini, -> { where(source: "gemini") }
  scope :from_manual, -> { where(source: "manual") }

  # 주어진 merchant 이름에 대한 매핑 찾기 (description_pattern이 nil인 기본 매핑)
  def self.find_for_merchant(workspace, merchant)
    return nil if merchant.blank?

    for_workspace(workspace)
      .where(merchant_pattern: merchant.strip)
      .where(description_pattern: [ nil, "" ])
      .first
  end

  # 주어진 merchant 이름에 대한 카테고리 찾기 (매핑이 있으면 반환)
  def self.find_category_for_merchant(workspace, merchant)
    mapping = find_for_merchant(workspace, merchant)
    mapping&.category
  end

  # 가맹점명 + 설명 조합으로 카테고리 찾기
  # 우선순위: 1. description_pattern 매칭 → 2. 기본 매핑 (description_pattern이 nil)
  def self.find_category_for_merchant_and_description(workspace, merchant, description = nil)
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
    find_category_for_merchant(workspace, merchant)
  end
end
