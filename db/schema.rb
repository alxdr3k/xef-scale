# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_25_132334) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "allowance_transactions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "expense_transaction_id", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["expense_transaction_id", "user_id"], name: "idx_on_expense_transaction_id_user_id_d9ae587c5a", unique: true
    t.index ["expense_transaction_id"], name: "index_allowance_transactions_on_expense_transaction_id"
    t.index ["user_id"], name: "index_allowance_transactions_on_user_id"
  end

  create_table "categories", force: :cascade do |t|
    t.string "color"
    t.datetime "created_at", null: false
    t.string "keyword"
    t.string "name"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id"], name: "index_categories_on_workspace_id"
  end

  create_table "category_mappings", force: :cascade do |t|
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.string "description_pattern"
    t.string "merchant_pattern", null: false
    t.string "source", default: "import"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["category_id"], name: "index_category_mappings_on_category_id"
    t.index ["workspace_id", "merchant_pattern", "description_pattern"], name: "idx_category_mappings_workspace_merchant_desc", unique: true
    t.index ["workspace_id"], name: "index_category_mappings_on_workspace_id"
  end

  create_table "duplicate_confirmations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "new_transaction_id", null: false
    t.integer "original_transaction_id", null: false
    t.integer "parsing_session_id", null: false
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["new_transaction_id"], name: "index_duplicate_confirmations_on_new_transaction_id"
    t.index ["original_transaction_id"], name: "index_duplicate_confirmations_on_original_transaction_id"
    t.index ["parsing_session_id"], name: "index_duplicate_confirmations_on_parsing_session_id"
  end

  create_table "financial_institutions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "identifier", null: false
    t.string "institution_type"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["identifier"], name: "index_financial_institutions_on_identifier", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.string "action_url"
    t.datetime "created_at", null: false
    t.text "message"
    t.integer "notifiable_id"
    t.string "notifiable_type"
    t.string "notification_type", null: false
    t.datetime "read_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
    t.index ["workspace_id"], name: "index_notifications_on_workspace_id"
  end

  create_table "parsing_sessions", force: :cascade do |t|
    t.datetime "committed_at"
    t.integer "committed_by_id"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "duplicate_count"
    t.integer "error_count"
    t.integer "processed_file_id", null: false
    t.string "review_status", default: "pending_review"
    t.datetime "rolled_back_at"
    t.integer "rolled_back_by_id"
    t.datetime "started_at"
    t.string "status"
    t.integer "success_count"
    t.integer "total_count"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["processed_file_id"], name: "index_parsing_sessions_on_processed_file_id"
    t.index ["review_status"], name: "index_parsing_sessions_on_review_status"
    t.index ["workspace_id"], name: "index_parsing_sessions_on_workspace_id"
  end

  create_table "processed_files", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_hash"
    t.string "filename"
    t.string "original_filename"
    t.string "status"
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["workspace_id"], name: "index_processed_files_on_workspace_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "benefit_amount"
    t.string "benefit_type"
    t.integer "category_id"
    t.datetime "committed_at"
    t.integer "committed_by_id"
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.boolean "deleted", default: false
    t.string "description"
    t.integer "financial_institution_id"
    t.integer "installment_month"
    t.integer "installment_total"
    t.string "merchant"
    t.text "notes"
    t.integer "original_amount"
    t.integer "parsing_session_id"
    t.string "status", default: "committed", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["date", "merchant", "amount"], name: "index_transactions_on_date_and_merchant_and_amount"
    t.index ["financial_institution_id"], name: "index_transactions_on_financial_institution_id"
    t.index ["parsing_session_id"], name: "index_transactions_on_parsing_session_id"
    t.index ["status"], name: "index_transactions_on_status"
    t.index ["workspace_id", "category_id"], name: "index_transactions_on_workspace_id_and_category_id"
    t.index ["workspace_id", "date"], name: "index_transactions_on_workspace_id_and_date"
    t.index ["workspace_id", "status"], name: "index_transactions_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_transactions_on_workspace_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.string "provider"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workspace_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_uses", default: 0
    t.datetime "expires_at"
    t.integer "invited_by_id", null: false
    t.integer "max_uses"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["invited_by_id"], name: "index_workspace_invitations_on_invited_by_id"
    t.index ["token"], name: "index_workspace_invitations_on_token", unique: true
    t.index ["workspace_id"], name: "index_workspace_invitations_on_workspace_id"
  end

  create_table "workspace_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["user_id"], name: "index_workspace_memberships_on_user_id"
    t.index ["workspace_id"], name: "index_workspace_memberships_on_workspace_id"
  end

  create_table "workspaces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "allowance_transactions", "transactions", column: "expense_transaction_id"
  add_foreign_key "allowance_transactions", "users"
  add_foreign_key "categories", "workspaces"
  add_foreign_key "category_mappings", "categories"
  add_foreign_key "category_mappings", "workspaces"
  add_foreign_key "duplicate_confirmations", "parsing_sessions"
  add_foreign_key "duplicate_confirmations", "transactions", column: "new_transaction_id"
  add_foreign_key "duplicate_confirmations", "transactions", column: "original_transaction_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "workspaces"
  add_foreign_key "parsing_sessions", "processed_files"
  add_foreign_key "parsing_sessions", "users", column: "committed_by_id"
  add_foreign_key "parsing_sessions", "users", column: "rolled_back_by_id"
  add_foreign_key "parsing_sessions", "workspaces"
  add_foreign_key "processed_files", "workspaces"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "financial_institutions"
  add_foreign_key "transactions", "parsing_sessions"
  add_foreign_key "transactions", "users", column: "committed_by_id"
  add_foreign_key "transactions", "workspaces"
  add_foreign_key "workspace_invitations", "users", column: "invited_by_id"
  add_foreign_key "workspace_invitations", "workspaces"
  add_foreign_key "workspace_memberships", "users"
  add_foreign_key "workspace_memberships", "workspaces"
  add_foreign_key "workspaces", "users", column: "owner_id"
end
