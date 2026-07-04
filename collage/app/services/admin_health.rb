# The admin "is the box alive?" snapshot — everything the health panel shows,
# computed in one place so the view only prints. Read-only; safe to call on every
# admin page load.
#
# Liveness is inferred from the most recent detection's heard-at time, because the
# detections table carries no ingest timestamp. That's an honest proxy — during the
# day birds are frequent enough that a stale "last heard" means the mic → BirdNET →
# push → RDS chain has stalled — but it can't tell a genuinely quiet night from a
# broken pipe. A dedicated push heartbeat (a ping every cycle, even empty ones) would
# make it unambiguous; that needs a listener-side change, so it's a follow-up.
class AdminHealth
  FRESH = 30.minutes  # green: heard something recently, chain is flowing
  QUIET = 6.hours     # amber: nothing lately — quiet, or possibly stalled

  class << self
    def snapshot(now: Time.current)
      new(now).snapshot
    end
  end

  def initialize(now)
    @now = now
  end

  def snapshot
    { listening: listening, alerts: alerts, system: system }
  end

  private

  def listening
    last = Detection.where.not(Date: nil).where.not(Time: nil).order(Date: :desc, Time: :desc).first
    heard = last&.heard_at
    {
      last_heard_at:       heard,
      last_heard_ago:      heard && (@now - heard),
      freshness:           freshness(heard),
      last_species:        last && BirdName.lookup(last.Sci_Name),
      detections_today:    Detection.today.count,
      detections_all_time: Detection.count,
      species_today:       Detection.tally_for.size,
      species_all_time:    Detection.life_list.size
    }
  end

  # fresh / quiet / stale — or none when nothing has ever been heard.
  def freshness(heard)
    return :none unless heard

    ago = @now - heard
    return :fresh if ago <= FRESH
    return :quiet if ago <= QUIET

    :stale
  end

  def alerts
    last = Event.order(created_at: :desc).first
    {
      configured:     ENV['ALERTS_FROM'].present?,
      from:           ENV.fetch('ALERTS_FROM', nil),
      following:      Subscription.active.where(alert_type: 'species').count,
      standing_rules: Subscription.active.where.not(alert_type: 'species').count,
      events_total:   Event.count,
      events_pending: Event.pending.count, # unsent backlog — should trend to 0
      last_event:     last && { type: last.event_type, name: BirdName.lookup(last.sci_name).en, at: last.created_at }
    }
  end

  def system
    {
      env:        Rails.env,
      adapter:    ActiveRecord::Base.connection.adapter_name,
      site_url:   ENV.fetch('SITE_URL', nil),
      llm_region: ENV.fetch('BEDROCK_REGION', nil)
    }
  end
end
