class AddReturnToToLoginTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :login_tokens, :return_to, :string
  end
end
