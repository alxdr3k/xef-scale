class AddDuplicateContextToImportIssues < ActiveRecord::Migration[8.1]
  def change
    add_column :import_issues, :issue_type, :string, null: false, default: "missing_required_fields"
    add_reference :import_issues, :duplicate_transaction, foreign_key: { to_table: :transactions }

    add_index :import_issues, [ :issue_type, :status ]
  end
end
