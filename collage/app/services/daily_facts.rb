# The facts engine. All reasoning about a day's detections lives here: counts,
# rankings, the two kinds of "first", local rarity, importance scoring, the 24h
# activity curve and a spotlight pick. It reads the detection store and returns a
# plain Hash — the facts object the summary prompt narrates and the pages render.
#
# Two rules keep the warmth honest:
#   * Ruby computes, the LLM only narrates. Every number and claim is decided here.
#   * Pure and offline. `for` touches only the database. The one lazy network hop
#     (the spotlight's background blurb) is opt-in via `spotlight_blurb:` so a page
#     load never fetches — only the summary refresh does.
class DailyFacts
  # A resident heard daily must never read as an "arrival". A species counts as a
  # seasonal first only if it was absent for this many days before today — closer
  # to what a birder means by "first of the year" than the calendar, and it avoids
  # flagging every resident on 1 January.
  ARRIVAL_WINDOW_DAYS = 30
  # Local rarity is measured against the station's own history: heard on only a
  # handful of the last N days is locally scarce; heard daily is not.
  RARE_WINDOW_DAYS = 200
  RARE_MAX_DAYS = 5
  # Rarity needs a baseline — in the first weeks everything looks rare, so hold the
  # signal until there's enough history for it to mean anything.
  RARE_MIN_AGE_DAYS = 30
  # In the first year every species is an all-time-first, which would flood the
  # "news". Until a full year's baseline exists, damp all-time-firsts so genuine
  # seasonal arrivals lead instead of "NEW!" about a House Sparrow on day two.
  YOUNG_STATION_DAYS = 365
  # Trailing days used for the coarse volume-anomaly / activity-note baselines.
  BASELINE_DAYS = 14
  # The loudest few tallies carry the "most_common" texture flag.
  MOST_COMMON_TOP = 3
  # Importance is the single integer the summary orders by; flags are metadata.
  NOTABLE_IMPORTANCE = 60
  IMPORTANCE = {
    all_time_first:       100,
    all_time_first_young: 70,
    year_first:           80,
    rare_local:           60,
    unusual_volume:       40,
    routine:              5
  }.freeze

  class << self
    # The whole facts object for a day. `spotlight_blurb:` gates the one network
    # hop, so /api/overview (default false) never fetches and the summary refresh
    # (true) does.
    def for(date: Date.current, now: Time.current, spotlight_blurb: false)
      new(date: date, now: now).to_h(spotlight_blurb: spotlight_blurb)
    end

    # Days since the station first heard anything — the "day N of listening" number
    # and the young-station guard. Zero before the first detection.
    def station_age_days(now: Time.current)
      first = Detection.minimum(:Date)
      first ? (now.to_date - first).to_i : 0
    end

    # The deterministic, always-correct fallback: pure Ruby bullets off the facts
    # hash, no model. Ugly but honest — used when there is no cached LLM summary.
    def template_bullets(facts)
      bullets = ["#{facts[:species_today]} species and " \
                 "#{facts[:detections_today]} detections logged today."]
      firsts = names_with(facts, 'all_time_first')
      years  = names_with(facts, 'year_first')
      common = facts[:items].select { |i| i[:flags].include?('most_common') }.first(3).pluck(:common_name)
      bullets << "New for the station: #{lead_phrase(firsts)}." if firsts.any?
      bullets << "First of the year: #{lead_phrase(years)}." if years.any?
      bullets << "Most heard: #{common.join(', ')}." if common.any? && bullets.length < 4
      bullets.first(4)
    end

    private

    def names_with(facts, flag)
      facts[:items].select { |i| i[:flags].include?(flag) }.pluck(:common_name)
    end

    # Name the single most important item; collapse the rest to "+N more" so a
    # bullet is never an unbounded comma-list of species (a layout contract).
    def lead_phrase(names)
      return names.first if names.length == 1

      "#{names.first}, and #{names.length - 1} more"
    end
  end

  attr_reader :date, :now

  def initialize(date: Date.current, now: Time.current)
    @date = date
    @now = now
  end

  def to_h(spotlight_blurb: false)
    {
      date:               @date.to_s,
      species_today:      today_tally.size,
      detections_today:   detections_today,
      items:              items,
      spotlight:          spotlight(include_blurb: spotlight_blurb),
      activity_note:      activity_note,
      activity_curve_24h: activity_curve_24h,
      notable_today:      items.select { |i| i[:importance] >= NOTABLE_IMPORTANCE },
      station_age_days:   station_age_days
    }
  end

  private

  def today_tally
    @today_tally ||= Detection.tally_for(date)
  end

  def detections_today
    @detections_today ||= Detection.on_date(date).count
  end

  def station_age_days
    @station_age_days ||= self.class.station_age_days(now: now)
  end

  def young_station?
    station_age_days < YOUNG_STATION_DAYS
  end

  # First-heard date per species, from the life list (one grouped query).
  def first_seen_dates
    @first_seen_dates ||= Detection.life_list.to_h do |entry|
      [entry.sci_name, parse_date(entry.first_seen)]
    end
  end

  # One scored item per credible species heard today, importance-ranked. The
  # loudest few carry the most_common texture flag.
  def items
    @items ||= today_tally.each_with_index.map { |tally, i| scored_item(tally, most_common: i < MOST_COMMON_TOP) }.
               sort_by { |item| [-item[:importance], -item[:call_count]] }
  end

  def scored_item(tally, most_common:)
    sci = tally.sci_name
    name = tally.name
    flags = []
    score = IMPORTANCE[:routine]

    if all_time_first?(sci)
      flags << 'all_time_first'
      score = young_station? ? IMPORTANCE[:all_time_first_young] : IMPORTANCE[:all_time_first]
    elsif year_first?(sci)
      flags << 'year_first'
      score = [score, IMPORTANCE[:year_first]].max
    end

    if rare_local?(sci)
      flags << 'rare_local'
      score = [score, IMPORTANCE[:rare_local]].max
    end

    if unusual_volume?(sci, tally.count)
      flags << 'unusual_volume'
      score = [score, IMPORTANCE[:unusual_volume]].max
    end

    flags << 'most_common' if most_common
    flags << 'routine' if flags.empty? || flags == ['most_common']

    {
      common_name: name.en, irish_name: name.ga, sci_name: sci,
      call_count: tally.count, importance: score, flags: flags
    }
  end

  # Never heard before today: the species' first-ever record is today.
  def all_time_first?(sci)
    first_seen_dates[sci] == date
  end

  # Heard today but absent for the whole arrival window before today (and not an
  # all-time-first). The seasonal-return signal.
  def year_first?(sci)
    return false if all_time_first?(sci)

    window = (date - ARRIVAL_WINDOW_DAYS)...date
    Detection.where(Sci_Name: sci, Date: window).none?
  end

  # Locally scarce: heard on only a handful of the last RARE_WINDOW_DAYS days.
  # Held until the station has a baseline worth measuring against.
  def rare_local?(sci)
    return false if station_age_days < RARE_MIN_AGE_DAYS

    window = (date - RARE_WINDOW_DAYS)..date
    days_heard = Detection.where(Sci_Name: sci, Date: window).distinct.count(:Date)
    days_heard.positive? && days_heard <= RARE_MAX_DAYS
  end

  # Today's count sits well outside this species' own recent daily average. Coarse
  # and conservative: silent until there's enough history, and only fires on a
  # clear departure from baseline.
  def unusual_volume?(sci, count_today)
    baseline = species_baseline(sci)
    return false unless baseline

    count_today > baseline * 2 || count_today < baseline * 0.5
  end

  # Mean daily count on the days this species was heard in the trailing window
  # (excluding today), or nil if too thin to trust.
  def species_baseline(sci)
    window = (date - BASELINE_DAYS)...date
    by_day = Detection.where(Sci_Name: sci, Date: window).group(:Date).count
    return nil if by_day.size < BASELINE_DAYS / 2

    by_day.values.sum.to_f / by_day.size
  end

  # The single species to feature: highest importance, ties broken all_time_first
  # > year_first > rare_local > loudest. The blurb (source material for the LLM) is
  # fetched only when asked, and cached per species by SpeciesInfo.
  def spotlight(include_blurb: false)
    top = items.min_by { |item| [-item[:importance], -tie_rank(item), -item[:call_count]] }
    return nil unless top

    context = rarity_context(top)
    result = { common_name: top[:common_name], irish_name: top[:irish_name], rarity_context: context }
    result[:blurb] = SpeciesInfo.english_for(top[:sci_name], top[:common_name]) if include_blurb
    result
  end

  def tie_rank(item)
    return 3 if item[:flags].include?('all_time_first')
    return 2 if item[:flags].include?('year_first')
    return 1 if item[:flags].include?('rare_local')

    0
  end

  # A factual one-liner about why the spotlight matters — true by construction.
  def rarity_context(item)
    if item[:flags].include?('all_time_first')
      'first record at the station'
    elsif item[:flags].include?('year_first')
      "first record here in over #{ARRIVAL_WINDOW_DAYS} days"
    elsif item[:flags].include?('rare_local')
      "heard on only a handful of the last #{RARE_WINDOW_DAYS} days"
    end
  end

  # Coarse label only — today's pace against a trailing same-time-of-day baseline.
  # The prompt turns the label into a phrase; the model never computes it.
  def activity_note
    baseline = daily_baseline
    return nil unless baseline

    fraction = ((now.hour + 1) / 24.0)
    expected = baseline * fraction
    return nil if expected.zero?

    ratio = detections_today / expected
    return :busier_than_typical if ratio > 1.5
    return :quieter_than_typical if ratio < 0.6

    :typical
  end

  # Mean total detections per day over the trailing window (excluding today), or
  # nil if there aren't enough days to mean anything.
  def daily_baseline
    window = (date - BASELINE_DAYS)...date
    by_day = Detection.where(Date: window).group(:Date).count
    return nil if by_day.size < BASELINE_DAYS / 2

    by_day.values.sum.to_f / by_day.size
  end

  # Detections bucketed into 24 hours — the data behind the home page sparkline.
  # Uses raw detections (matching detections_today), DB-agnostic via the Time cast.
  def activity_curve_24h
    counts = Array.new(24, 0)
    Detection.on_date(date).pluck(:Time).each do |value|
      hour = hour_of(value)
      counts[hour] += 1 if hour
    end
    counts.each_index.map { |hour| { hour: hour, count: counts[hour] } }
  end

  def hour_of(value)
    return nil unless value
    return value.hour if value.respond_to?(:hour)

    Time.zone.parse(value.to_s)&.hour
  end

  def parse_date(value)
    return value if value.is_a?(Date)

    Date.parse(value.to_s[0, 10])
  rescue ArgumentError, TypeError
    nil
  end
end
