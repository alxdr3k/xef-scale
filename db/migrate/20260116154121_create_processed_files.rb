class CreateProcessedFiles < ActiveRecord::Migration[8.1]
  def change
    create_table :processed_files do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :filename
      t.string :original_filename
      t.string :file_hash
      t.string :status

      t.timestamps
    end
  end
end
