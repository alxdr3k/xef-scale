class Comment < ApplicationRecord
  belongs_to :commentable_transaction, class_name: "Transaction", foreign_key: :transaction_id, counter_cache: :comments_count
  belongs_to :user

  validates :body, presence: true, length: { maximum: 2000 }

  scope :ordered, -> { order(created_at: :asc) }
end
