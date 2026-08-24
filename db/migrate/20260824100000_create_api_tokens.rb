class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :scope, null: false
      t.datetime :expires_at
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps

      t.index :token_digest, unique: true
      t.index [ :user_id, :name ], unique: true, where: "revoked_at IS NULL"
      t.check_constraint "scope IN ('read', 'write')", name: "api_tokens_scope"
      t.check_constraint "length(trim(name)) BETWEEN 1 AND 60", name: "api_tokens_name_length"
    end
  end
end
