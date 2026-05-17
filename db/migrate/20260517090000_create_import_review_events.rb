class CreateImportReviewEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :import_review_events do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :parsing_session, null: false, foreign_key: true
      t.references :reviewed_transaction, foreign_key: { to_table: :transactions }
      t.string :event_type, null: false
      t.text :changed_fields, null: false, default: "[]"

      t.timestamps
    end

    add_index :import_review_events, [ :parsing_session_id, :event_type ]
    add_index :import_review_events, [ :workspace_id, :created_at ]
  end
end
