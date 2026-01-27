class AddUploadedByToProcessedFiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :processed_files, :uploaded_by, null: true, foreign_key: { to_table: :users }
  end
end
