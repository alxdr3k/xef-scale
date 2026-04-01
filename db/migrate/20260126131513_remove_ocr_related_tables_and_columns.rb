class RemoveOcrRelatedTablesAndColumns < ActiveRecord::Migration[8.1]
  def change
    drop_table :api_tokens, if_exists: true

    remove_column :processed_files, :ocr_request_id, :string, if_exists: true
    remove_column :processed_files, :ocr_requested_at, :datetime, if_exists: true
    remove_column :processed_files, :ocr_attempts, :integer, if_exists: true
  end
end
