class AddMatchTypeAndAmountToCategoryMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :category_mappings, :match_type, :string, default: "exact", null: false
    add_column :category_mappings, :amount, :integer, null: true

    # 기존 unique index 교체 (match_type, amount 포함)
    remove_index :category_mappings, name: "idx_category_mappings_workspace_merchant_desc"
    add_index :category_mappings,
              [:workspace_id, :merchant_pattern, :description_pattern, :match_type, :amount],
              unique: true, name: "idx_category_mappings_unique"
  end
end
