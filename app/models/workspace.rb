class Workspace < ApplicationRecord
  belongs_to :owner, class_name: "User"

  has_many :workspace_memberships, dependent: :destroy
  has_many :members, through: :workspace_memberships, source: :user
  has_many :workspace_invitations, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :category_mappings, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :processed_files, dependent: :destroy
  has_many :parsing_sessions, dependent: :destroy
  has_many :import_issues, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_one :budget, dependent: :destroy

  validates :name, presence: true

  after_create :add_owner_as_member
  after_create :create_default_categories

  # The user has not yet acknowledged that AI features (text/image parsing
  # and category suggestions) send data to an external provider. The review
  # workflow shows a one-time consent banner while this is true.
  def ai_consent_required?
    ai_consent_acknowledged_at.nil? && (
      ai_text_parsing_enabled? || ai_image_parsing_enabled? || ai_category_suggestions_enabled?
    )
  end

  def acknowledge_ai_consent!
    update!(ai_consent_acknowledged_at: Time.current)
  end

  def admins
    members.joins(:workspace_memberships)
           .where(workspace_memberships: { workspace_id: id, role: %w[owner co_owner] })
  end

  private

  def add_owner_as_member
    workspace_memberships.create!(user: owner, role: "owner")
  end

  def create_default_categories
    default_categories = [
      { name: "식비", keyword: "식당,음식,배달,마라탕,치킨,피자", color: "#FF6B6B" },
      { name: "편의점/마트", keyword: "GS25,CU,세븐일레븐,이마트,홈플러스", color: "#4ECDC4" },
      { name: "교통/자동차", keyword: "주유,택시,지하철,버스,카카오T", color: "#45B7D1" },
      { name: "주거/통신", keyword: "통신,인터넷,전기,가스,수도", color: "#96CEB4" },
      { name: "쇼핑", keyword: "쿠팡,네이버,무신사,옥션", color: "#DDA0DD" },
      { name: "문화/여가", keyword: "영화,넷플릭스,게임,OTT", color: "#FFB347" },
      { name: "의료/건강", keyword: "병원,약국,헬스,운동", color: "#87CEEB" },
      { name: "보험", keyword: "보험,삼성생명,현대해상", color: "#C0C0C0" },
      { name: "기타", keyword: "", color: "#D3D3D3" }
    ]

    default_categories.each do |cat|
      categories.create!(cat)
    end
  end
end
