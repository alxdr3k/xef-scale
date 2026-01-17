class AddCommitStatusToParsingSessions < ActiveRecord::Migration[8.0]
  def change
    add_column :parsing_sessions, :review_status, :string, default: 'pending_review'
    add_column :parsing_sessions, :committed_at, :datetime
    add_column :parsing_sessions, :committed_by_id, :integer
    add_column :parsing_sessions, :rolled_back_at, :datetime
    add_column :parsing_sessions, :rolled_back_by_id, :integer

    add_index :parsing_sessions, :review_status
    add_foreign_key :parsing_sessions, :users, column: :committed_by_id
    add_foreign_key :parsing_sessions, :users, column: :rolled_back_by_id
  end
end
