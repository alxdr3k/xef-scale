class CreateParsingSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :parsing_sessions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :processed_file, null: false, foreign_key: true
      t.string :status
      t.integer :total_count
      t.integer :success_count
      t.integer :duplicate_count
      t.integer :error_count
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
