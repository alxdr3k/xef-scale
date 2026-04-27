class AddInstitutionIdentifierToProcessedFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :processed_files, :institution_identifier, :string
  end
end
