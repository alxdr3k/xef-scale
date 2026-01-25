class AddNotesPatternToCategoryMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :category_mappings, :notes_pattern, :string

    # 기존 unique 인덱스 제거
    remove_index :category_mappings, name: "idx_category_mappings_workspace_merchant"

    # 새 복합 unique 인덱스 추가 (merchant_pattern + notes_pattern)
    add_index :category_mappings, [ :workspace_id, :merchant_pattern, :notes_pattern ],
              unique: true,
              name: "idx_category_mappings_workspace_merchant_notes"
  end
end
