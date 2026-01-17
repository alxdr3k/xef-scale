class CreateFinancialInstitutions < ActiveRecord::Migration[8.1]
  def change
    create_table :financial_institutions do |t|
      t.string :name, null: false
      t.string :identifier, null: false
      t.string :institution_type  # bank, card, pay, etc.

      t.timestamps
    end
    add_index :financial_institutions, :identifier, unique: true
  end
end
