class EnforceImportIssueMissingFieldsDefault < ActiveRecord::Migration[8.1]
  def change
    change_column_default :import_issues, :missing_fields, from: nil, to: "[]"
    change_column_null :import_issues, :missing_fields, false, "[]"
  end
end
