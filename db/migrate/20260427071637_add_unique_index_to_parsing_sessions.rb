class AddUniqueIndexToParsingSessions < ActiveRecord::Migration[8.1]
  def up
    duplicate_session_ids = ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT id FROM parsing_sessions
      WHERE processed_file_id IS NOT NULL
        AND id NOT IN (
          SELECT MAX(id)
          FROM parsing_sessions
          WHERE processed_file_id IS NOT NULL
          GROUP BY processed_file_id
        )
    SQL

    if duplicate_session_ids.any?
      sessions_in = sql_in_clause(duplicate_session_ids)

      transaction_ids = ActiveRecord::Base.connection.select_values(
        "SELECT id FROM transactions WHERE parsing_session_id IN #{sessions_in}"
      )

      if transaction_ids.any?
        tx_in = sql_in_clause(transaction_ids)
        execute "DELETE FROM allowance_transactions WHERE expense_transaction_id IN #{tx_in}"
        execute "DELETE FROM comments WHERE transaction_id IN #{tx_in}"
        execute "DELETE FROM duplicate_confirmations WHERE new_transaction_id IN #{tx_in} OR original_transaction_id IN #{tx_in}"
      end

      execute "DELETE FROM duplicate_confirmations WHERE parsing_session_id IN #{sessions_in}"
      execute "DELETE FROM transactions WHERE parsing_session_id IN #{sessions_in}"
      execute "DELETE FROM parsing_sessions WHERE id IN #{sessions_in}"
    end

    remove_index :parsing_sessions, :processed_file_id,
                 name: "index_parsing_sessions_on_processed_file_id",
                 if_exists: true

    add_index :parsing_sessions, :processed_file_id,
              unique: true,
              where: "processed_file_id IS NOT NULL",
              name: "index_parsing_sessions_on_processed_file_id_unique"
  end

  def down
    remove_index :parsing_sessions, :processed_file_id,
                 name: "index_parsing_sessions_on_processed_file_id_unique",
                 if_exists: true

    add_index :parsing_sessions, :processed_file_id,
              name: "index_parsing_sessions_on_processed_file_id"
  end

  private

  def sql_in_clause(ids)
    placeholders = ids.map { "?" }.join(",")
    ActiveRecord::Base.send(:sanitize_sql_array, [ "(#{placeholders})", *ids ])
  end
end
