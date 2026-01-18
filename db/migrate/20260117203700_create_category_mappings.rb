# frozen_string_literal: true

class CreateCategoryMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :category_mappings do |t|
      t.string :merchant_pattern, null: false
      t.references :category, null: false, foreign_key: true
      t.references :workspace, null: false, foreign_key: true
      t.string :source, default: 'import' # 'import', 'gemini', 'manual'

      t.timestamps
    end

    add_index :category_mappings, [:workspace_id, :merchant_pattern], unique: true, name: 'idx_category_mappings_workspace_merchant'
  end
end
