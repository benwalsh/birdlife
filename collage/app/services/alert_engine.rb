# Runs after each ingest batch: turns newly-arrived species into fire-once
# `events`, then emails the matching subscribers. Best-effort and queue-free — a
# send failure leaves the event unsent, so the next ingest tick retries it.
#
# This is the "after_create :notify!" the ingest can't use directly: `upsert_all`
# skips ActiveRecord callbacks, so the trigger lives here, at the batch level.
class AlertEngine
  class << self
    def scan(sci_names)
      new(Array(sci_names).compact.uniq).run
    end
  end

  def initialize(sci_names)
    @sci_names = sci_names
  end

  def run
    record_events
    deliver_pending
  end

  private

  def record_events
    @sci_names.each do |sci|
      record('first_ever', sci) if first_ever?(sci)
      record('species', sci) if subscribed?(sci)
    end
  end

  def deliver_pending
    Event.pending.find_each do |event|
      recipients = subscriptions_for(event)
      delivered = recipients.map { |sub| Notifier.deliver(event:, subscription: sub) }
      # Mark done only if every recipient succeeded (none = nothing to retry); a
      # failure leaves notified_at nil so the next tick retries.
      event.mark_notified! if delivered.all?
    end
  end

  def record(type, sci)
    Event.find_or_create_by!(event_type: type, sci_name: sci, occurred_on: Date.current)
  rescue ActiveRecord::RecordNotUnique
    # A concurrent ingest already recorded it — fine, it's fire-once by design.
  end

  # First time ever: this species has no detections dated before today.
  def first_ever?(sci)
    Detection.where(Sci_Name: sci).where(Date: ..Date.yesterday).none?
  end

  def subscribed?(sci)
    Subscription.for_species(sci).exists?
  end

  def subscriptions_for(event)
    if event.event_type == 'species'
      Subscription.for_species(event.sci_name)
    else
      Subscription.of_type(event.event_type)
    end
  end
end
