# frozen_string_literal: true

class CategoryMapping < ApplicationRecord
  belongs_to :category
  belongs_to :workspace

  SOURCES = %w[import gemini manual].freeze

  validates :merchant_pattern, presence: true
  validates :merchant_pattern, uniqueness: { scope: :workspace_id, message: '이미 등록된 매핑입니다' }
  validates :source, inclusion: { in: SOURCES }

  scope :for_workspace, ->(workspace) { where(workspace: workspace) }
  scope :from_import, -> { where(source: 'import') }
  scope :from_gemini, -> { where(source: 'gemini') }
  scope :from_manual, -> { where(source: 'manual') }

  # 주어진 merchant 이름에 대한 매핑 찾기
  def self.find_for_merchant(workspace, merchant)
    return nil if merchant.blank?

    for_workspace(workspace).find_by(merchant_pattern: merchant.strip)
  end

  # 주어진 merchant 이름에 대한 카테고리 찾기 (매핑이 있으면 반환)
  def self.find_category_for_merchant(workspace, merchant)
    mapping = find_for_merchant(workspace, merchant)
    mapping&.category
  end
end
