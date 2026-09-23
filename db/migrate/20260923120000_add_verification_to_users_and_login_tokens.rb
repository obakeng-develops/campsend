class AddVerificationToUsersAndLoginTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :verified_at, :datetime
    add_reference :login_tokens, :send, foreign_key: { on_delete: :nullify }
    # Everyone who exists today operated under the old rules, where an address
    # could send as soon as its link was clicked. Nothing is taken from them.
    execute "UPDATE users SET verified_at = created_at"
  end

  def down
    remove_reference :login_tokens, :send
    remove_column :users, :verified_at
  end
end
