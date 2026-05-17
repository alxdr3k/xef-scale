class CreateImportIssues < ActiveRecord::Migration[8.1]
  def change
    create_table :import_issues do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :parsing_session, null: false, foreign_key: true
      t.references :processed_file, foreign_key: true
      t.references :resolved_transaction, foreign_key: { to_table: :transactions }
      t.string :source_type, null: false
      t.string :status, null: false, default: "open"
      t.date :date
      t.string :merchant
      t.integer :amount
      t.text :missing_fields, null: false, default: "[]"
      t.text :raw_payload

      t.timestamps
    end

    add_index :import_issues, [ :workspace_id, :status ]
    add_index :import_issues, [ :parsing_session_id, :status ]
    add_index :import_issues, [ :source_type, :status ]
  end
end
