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

ActiveRecord::Schema[8.1].define(version: 2026_08_27_120000) do
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
    t.integer "uploader_id"
    t.index ["id", "uploader_id"], name: "index_active_storage_blobs_on_id_and_uploader_id", unique: true
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
    t.index ["uploader_id"], name: "index_active_storage_blobs_on_uploader_id"
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "scope", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id", "name"], name: "index_api_tokens_on_user_id_and_name", unique: true, where: "revoked_at IS NULL"
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
    t.check_constraint "length(trim(name)) BETWEEN 1 AND 60", name: "api_tokens_name_length"
    t.check_constraint "scope IN ('read', 'write')", name: "api_tokens_scope"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.bigint "actor_id"
    t.string "actor_label"
    t.string "actor_type", null: false
    t.json "changed_fields"
    t.string "denial_reason"
    t.datetime "occurred_at", null: false
    t.string "outcome", null: false
    t.datetime "recorded_at", null: false
    t.string "request_id"
    t.bigint "target_id"
    t.string "target_label"
    t.string "target_type"
    t.index ["actor_type", "actor_id", "occurred_at"], name: "index_audit_events_on_actor_type_and_actor_id_and_occurred_at"
    t.index ["occurred_at"], name: "index_audit_events_on_occurred_at"
    t.index ["target_type", "target_id", "occurred_at"], name: "idx_on_target_type_target_id_occurred_at_b7d56dd404"
    t.check_constraint "outcome IN ('succeeded', 'denied')", name: "audit_events_outcome"
  end

  create_table "collection_files", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.integer "collection_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["blob_id"], name: "index_collection_files_on_blob_id"
    t.index ["collection_id", "blob_id"], name: "index_collection_files_on_collection_id_and_blob_id", unique: true
    t.index ["collection_id", "position"], name: "index_collection_files_on_collection_id_and_position", unique: true
    t.index ["collection_id"], name: "index_collection_files_on_collection_id"
    t.index ["user_id"], name: "index_collection_files_on_user_id"
    t.check_constraint "position > 0", name: "collection_files_positive_position"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "removed_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["id", "user_id"], name: "index_collections_on_id_and_user_id", unique: true
    t.index ["user_id", "name"], name: "index_collections_on_user_id_and_name", unique: true, where: "removed_at IS NULL"
    t.index ["user_id"], name: "index_collections_on_user_id"
    t.check_constraint "length(trim(name)) BETWEEN 1 AND 100", name: "collections_name_length"
  end

  create_table "delivery_revisions", force: :cascade do |t|
    t.string "collection_name"
    t.datetime "created_at", null: false
    t.integer "number", null: false
    t.integer "send_id", null: false
    t.datetime "updated_at", null: false
    t.index ["send_id", "number"], name: "index_delivery_revisions_on_send_id_and_number", unique: true
    t.index ["send_id"], name: "index_delivery_revisions_on_send_id"
  end

  create_table "google_drive_imports", force: :cascade do |t|
    t.integer "blob_id"
    t.datetime "created_at", null: false
    t.string "error"
    t.string "filename", null: false
    t.string "google_file_id", null: false
    t.string "resource_key"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["blob_id"], name: "index_google_drive_imports_on_blob_id"
    t.index ["user_id", "status"], name: "index_google_drive_imports_on_user_id_and_status"
    t.index ["user_id"], name: "index_google_drive_imports_on_user_id"
  end

  create_table "login_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "intent"
    t.string "public_id", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.integer "user_id", null: false
    t.index ["public_id"], name: "index_login_tokens_on_public_id", unique: true
    t.index ["token_digest"], name: "index_login_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_login_tokens_on_user_id"
  end

  create_table "send_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.datetime "occurred_at", null: false
    t.integer "send_id", null: false
    t.datetime "updated_at", null: false
    t.index ["send_id", "event_type"], name: "index_send_events_on_send_id_and_event_type", unique: true
    t.index ["send_id"], name: "index_send_events_on_send_id"
  end

  create_table "sends", force: :cascade do |t|
    t.datetime "access_expires_at"
    t.datetime "access_revoked_at"
    t.string "access_token_digest"
    t.datetime "canceled_at"
    t.integer "collection_id"
    t.datetime "created_at", null: false
    t.string "email_status", default: "pending", null: false
    t.text "message"
    t.string "public_id", null: false
    t.datetime "publication_enqueued_at"
    t.datetime "published_at"
    t.string "recipient_email", null: false
    t.datetime "scheduled_at"
    t.string "slug"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["access_token_digest"], name: "index_sends_on_access_token_digest", unique: true
    t.index ["canceled_at", "published_at", "scheduled_at"], name: "index_sends_on_canceled_at_and_published_at_and_scheduled_at"
    t.index ["collection_id"], name: "index_sends_on_collection_id"
    t.index ["public_id"], name: "index_sends_on_public_id", unique: true
    t.index ["published_at"], name: "index_sends_on_published_at"
    t.index ["recipient_email"], name: "index_sends_on_recipient_email"
    t.index ["slug"], name: "index_sends_on_slug", unique: true
    t.index ["user_id"], name: "index_sends_on_user_id"
    t.check_constraint "published_at IS NULL OR canceled_at IS NULL", name: "sends_publication_state"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_blobs", "users", column: "uploader_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "collection_files", "active_storage_blobs", column: ["blob_id", "user_id"], primary_key: ["id", "uploader_id"]
  add_foreign_key "collection_files", "collections", column: ["collection_id", "user_id"], primary_key: ["id", "user_id"]
  add_foreign_key "collection_files", "users"
  add_foreign_key "collections", "users"
  add_foreign_key "delivery_revisions", "sends"
  add_foreign_key "google_drive_imports", "active_storage_blobs", column: "blob_id", on_delete: :nullify
  add_foreign_key "google_drive_imports", "users"
  add_foreign_key "login_tokens", "users"
  add_foreign_key "send_events", "sends"
  add_foreign_key "sends", "collections", column: ["collection_id", "user_id"], primary_key: ["id", "user_id"]
  add_foreign_key "sends", "users"
end
