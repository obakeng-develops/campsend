class ActivityController < ApplicationController
  PER_PAGE = 50

  def index
    @action_filter = params[:audit_action].presence
    @from = parse_date(params[:from])
    @to = parse_date(params[:to])

    @events = AuditEvent.for_account(current_user)
                        .with_action(@action_filter)
                        .since(@from)
                        .until_end_of(@to)
                        .newest_first
                        .limit(PER_PAGE)
                        .to_a

    # The filter offers what this account has actually done, so it can't suggest
    # an action that returns nothing.
    @available_actions = AuditEvent.for_account(current_user).distinct.pluck(:action).sort
  end

  private
    def parse_date(value)
      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end
end
