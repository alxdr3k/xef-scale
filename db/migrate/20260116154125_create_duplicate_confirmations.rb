class CreateDuplicateConfirmations < ActiveRecord::Migration[8.1]
  def change
    create_table :duplicate_confirmations do |t|
      t.references :parsing_session, null: false, foreign_key: true
      t.references :original_transaction, null: false, foreign_key: { to_table: :transactions }
      t.references :new_transaction, null: false, foreign_key: { to_table: :transactions }
      t.string :status, default: 'pending'

      t.timestamps
    end
  end
end
