class RenameNotesPatternToDescriptionPatternInCategoryMappings < ActiveRecord::Migration[8.1]
  def change
    # 기존 인덱스 제거
    remove_index :category_mappings, name: "idx_category_mappings_workspace_merchant_notes"

    # 컬럼명 변경
    rename_column :category_mappings, :notes_pattern, :description_pattern

    # 새 인덱스 추가
    add_index :category_mappings, [ :workspace_id, :merchant_pattern, :description_pattern ],
              unique: true,
              name: "idx_category_mappings_workspace_merchant_desc"
  end
end
