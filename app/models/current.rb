# Who is acting, for the audit log.
#
# Model methods like Send#revoke_access! record what happened, and they have no
# way to know who called them. Threading an actor through every signature would
# be a wide change for one feature, so the entry points set it here instead.
#
# Unset means system: a job, a console, or a request that never authenticated.
class Current < ActiveSupport::CurrentAttributes
  attribute :actor

  # The triple AuditEvent stores: type, id, and a label snapshotted now.
  def self.actor_identity
    actor_identity_for(actor)
  end

  def self.actor_identity_for(subject)
    case subject
    when User     then [ "user", subject.id, subject.email_address ]
    when ApiToken then [ "api_token", subject.id, subject.name ]
    when String   then [ "recipient", nil, subject ]
    else               [ "system", nil, nil ]
    end
  end
end
