class FinancialInstitution < ApplicationRecord
  has_many :transactions, dependent: :nullify

  TYPES = %w[bank card pay].freeze

  validates :name, presence: true
  validates :identifier, presence: true, uniqueness: true

  scope :banks, -> { where(institution_type: 'bank') }
  scope :cards, -> { where(institution_type: 'card') }
  scope :pays, -> { where(institution_type: 'pay') }

  # 지원 금융기관 시드 데이터
  SUPPORTED_INSTITUTIONS = [
    { name: '신한카드', identifier: 'shinhan_card', institution_type: 'card' },
    { name: '하나카드', identifier: 'hana_card', institution_type: 'card' },
    { name: '토스뱅크', identifier: 'toss_bank', institution_type: 'bank' },
    { name: '토스페이', identifier: 'toss_pay', institution_type: 'pay' },
    { name: '카카오뱅크', identifier: 'kakao_bank', institution_type: 'bank' },
    { name: '카카오페이', identifier: 'kakao_pay', institution_type: 'pay' }
  ].freeze

  def self.seed_default!
    SUPPORTED_INSTITUTIONS.each do |attrs|
      find_or_create_by!(identifier: attrs[:identifier]) do |fi|
        fi.name = attrs[:name]
        fi.institution_type = attrs[:institution_type]
      end
    end
  end
end
