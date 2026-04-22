class AddDedupSignatureToCategoryMappings < ActiveRecord::Migration[8.1]
  def up
    add_column :category_mappings, :dedup_signature, :string

    backfill_dedup_signatures!
    drop_duplicates_keeping_latest!

    remove_index :category_mappings, name: "idx_category_mappings_unique"
    add_index :category_mappings, [ :workspace_id, :dedup_signature ],
              name: "idx_category_mappings_unique", unique: true
    change_column_null :category_mappings, :dedup_signature, false
  end

  def down
    remove_index :category_mappings, name: "idx_category_mappings_unique"
    add_index :category_mappings,
              [ :workspace_id, :merchant_pattern, :description_pattern, :match_type, :amount ],
              name: "idx_category_mappings_unique", unique: true
    remove_column :category_mappings, :dedup_signature
  end

  private

  # Signature format mirrors CategoryMapping#compute_dedup_signature so
  # Rails-level and DB-level uniqueness agree. Keep this string stable —
  # the DB unique index is built on it.
  def compute_signature(row)
    [
      row["merchant_pattern"].to_s,
      row["description_pattern"].to_s,
      row["match_type"].to_s,
      row["amount"].to_s
    ].join("\x1F")
  end

  def backfill_dedup_signatures!
    connection.execute("SELECT id, merchant_pattern, description_pattern, match_type, amount FROM category_mappings").each do |row|
      row = row.is_a?(Hash) ? row : Hash[%w[id merchant_pattern description_pattern match_type amount].zip(row)]
      connection.exec_update(
        "UPDATE category_mappings SET dedup_signature = ? WHERE id = ?",
        "backfill_category_mapping_signature",
        [ compute_signature(row), row["id"] ]
      )
    end
  end

  def drop_duplicates_keeping_latest!
    # Remove duplicate (workspace_id, dedup_signature) rows; keep the most
    # recently updated row. Without this, the new unique index would fail to
    # create on databases that already have NULL-amount duplicates introduced
    # by the old indexing semantics.
    duplicates = connection.exec_query(<<~SQL).to_a
      SELECT workspace_id, dedup_signature
      FROM category_mappings
      GROUP BY workspace_id, dedup_signature
      HAVING COUNT(*) > 1
    SQL

    duplicates.each do |dupe|
      ids = connection.exec_query(
        connection.send(:sanitize_sql_array, [
          "SELECT id FROM category_mappings WHERE workspace_id = ? AND dedup_signature = ? ORDER BY updated_at DESC, id DESC",
          dupe["workspace_id"], dupe["dedup_signature"]
        ])
      ).rows.flatten

      keep_id = ids.shift
      connection.exec_delete(
        "DELETE FROM category_mappings WHERE id IN (#{ids.map { '?' }.join(',')})",
        "dedup_category_mapping_cleanup",
        ids
      ) if ids.any?
      say "  Deduped category_mappings (ws=#{dupe['workspace_id']}, kept id=#{keep_id}, removed #{ids.size})"
    end
  end
end
