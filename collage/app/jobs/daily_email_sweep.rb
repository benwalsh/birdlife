# The once-a-day cloud sweep, run on a recurring schedule by Solid Queue (see
# config/recurring.yml). Two halves, in order:
#   1. Enrichment::Builder.run — source the day's DUE enrichment (Claude), the
#      importance backoff deciding which birds are worth a fresh lookup.
#   2. DailyDigest.deliver_all — assemble each subscriber's letter (Nova) and send it
#      (SES).
# Both halves are idempotent: enrichment reuses still-fresh bundles rather than
# re-sourcing, and DailyDigest skips any user already sent for the day (last_digest_on).
# So a retry — or a second run in the same day — is safe. Defaults to yesterday, the
# last complete day of detections.
class DailyEmailSweep < ApplicationJob
  queue_as :default

  def perform(date = Date.yesterday)
    date = Date.parse(date) if date.is_a?(String)
    Enrichment::Builder.run(date: date)
    DailyDigest.deliver_all(date: date)
  end
end
