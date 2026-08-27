class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.string :action, null: false
      t.string :outcome, null: false
      t.string :denial_reason

      # Ids are nullable and labels are snapshots, so a deleted user or delivery
      # still reads as itself a year later.
      t.string :actor_type, null: false
      t.bigint :actor_id
      t.string :actor_label
      t.string :target_type
      t.bigint :target_id
      t.string :target_label

      # Not "changes": that name collides with ActiveRecord::Dirty#changes and
      # Rails refuses to define the attribute.
      t.json :changed_fields
      t.string :request_id

      t.datetime :occurred_at, null: false
      t.datetime :recorded_at, null: false

      t.index [ :actor_type, :actor_id, :occurred_at ]
      t.index [ :target_type, :target_id, :occurred_at ]
      t.index :occurred_at
      t.check_constraint "outcome IN ('succeeded', 'denied')", name: "audit_events_outcome"
    end
  end
end
