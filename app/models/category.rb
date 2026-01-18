class Category < ApplicationRecord
  belongs_to :workspace
  has_many :transactions, dependent: :nullify
  has_many :category_mappings, dependent: :destroy

  validates :name, presence: true
  validates :name, uniqueness: { scope: :workspace_id }

  def keywords_array
    (keyword || '').split(',').map(&:strip).reject(&:blank?)
  end

  def matches?(text)
    return false if text.blank?
    keywords_array.any? { |kw| text.downcase.include?(kw.downcase) }
  end
end
