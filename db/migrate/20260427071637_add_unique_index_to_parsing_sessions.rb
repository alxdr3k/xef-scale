class AddUniqueIndexToParsingSessions < ActiveRecord::Migration[8.1]
  def up
    # Remove duplicate parsing sessions, keeping the most recent per processed_file
    execute <<~SQL
      DELETE FROM parsing_sessions
      WHERE processed_file_id IS NOT NULL
        AND id NOT IN (
          SELECT MAX(id)
          FROM parsing_sessions
          WHERE processed_file_id IS NOT NULL
          GROUP BY processed_file_id
        )
    SQL

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
end
