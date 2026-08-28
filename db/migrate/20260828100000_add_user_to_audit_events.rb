class AddUserToAuditEvents < ActiveRecord::Migration[8.1]
  def change
    # Whose log this row belongs to. Without it, "show me my activity" is a union
    # of subqueries over every target type, which is both slow and easy to get
    # wrong. auditlog.dev calls this workspace_id and lists it under core
    # identity for the same reason.
    #
    # No foreign key: deleting the account must not take the log with it.
    add_column :audit_events, :user_id, :bigint
    add_index :audit_events, [ :user_id, :occurred_at ]
    add_index :audit_events, [ :user_id, :action, :occurred_at ]
  end
end
