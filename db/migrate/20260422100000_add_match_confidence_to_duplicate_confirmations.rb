class AddMatchConfidenceToDuplicateConfirmations < ActiveRecord::Migration[8.0]
  def change
    add_column :duplicate_confirmations, :match_confidence, :string, default: "medium", null: false
    add_column :duplicate_confirmations, :match_score, :integer
  end
end
