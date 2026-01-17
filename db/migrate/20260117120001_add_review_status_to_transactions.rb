class AddReviewStatusToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :status, :string, default: 'committed', null: false
    add_column :transactions, :parsing_session_id, :integer
    add_column :transactions, :committed_at, :datetime
    add_column :transactions, :committed_by_id, :integer

    add_index :transactions, :status
    add_index :transactions, :parsing_session_id
    add_index :transactions, [:workspace_id, :status]
    add_foreign_key :transactions, :parsing_sessions, column: :parsing_session_id
    add_foreign_key :transactions, :users, column: :committed_by_id
  end
end
