class AddBlobPurgedAtToProcessedFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :processed_files, :blob_purged_at, :datetime
    add_index :processed_files, :blob_purged_at
  end
end
