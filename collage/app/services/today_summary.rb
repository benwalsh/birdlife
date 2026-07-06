require 'json'

# The home page's daily "today" summary — 2–4 warm-but-factual bullets. Ruby has
# already done all the reasoning (see DailyFacts); this only asks Nova Lite to turn
# a correct facts object into readable prose, then caches the result to disk.
#
# The page never blocks on the model: it always reads the last-good cache
# (`current`). A scheduled `refresh` regenerates. If the model is unreachable the
# last-good summary stays; only when there is no cache at all do we fall through to
# the deterministic, always-correct template. So warmth never costs accuracy or
# availability.
class TodaySummary
  STORE = Rails.root.join('storage/today_summary.json')

  # Verbatim from today_summary_prompt.md — the factual rules are absolute and the
  # summary layer is only trustworthy because these travel with the request. The
  # location is not hard-coded: `%<where>s` is filled from Station (config/API).
  SYSTEM = <<~PROMPT.freeze
    You write a short daily summary for a bird-listening station%<where>s. It
    detects birds by sound and logs them.

    Write 2 to 4 bullet points summarising today, based ONLY on the facts you are
    given. Lead with the most important items (highest importance score). New
    arrivals are the news — an all-time first or a year-first is what a reader
    most wants to know. Never return more than four bullets. If more than two
    species are flagged as firsts today, feature the two most important and fold the
    remaining firsts into one line (e.g. "with first records also of X, Y and Z").

    A species is a "first" ONLY if its facts line carries an all_time_first or
    year_first flag. If NOTHING today carries such a flag, do NOT call any bird a
    first, a new arrival, or newly detected — those words would be untrue. Just report
    the day plainly: the totals, and the most-heard species as texture.

    TONE: warm but understated. This is a quiet rural station, not a nature
    documentary. A little character is welcome in how you connect facts. Restraint
    over enthusiasm.

    FACTUAL RULES — these are absolute:
    - State ONLY what is in the facts. Every clause must trace to a given field.
    - Do NOT invent or imply bird behaviour, migration, motivation, origin, or
      destination. You do not know why a bird was heard or where it came from.
    - Do NOT link birds to weather, wind, temperature, or sky. The station cannot
      observe that a bird "arrived on" any weather. Never write such a link.
    - Tide may be mentioned ONLY for an item that carries a tide phase field, and
      ONLY as co-occurrence ("heard near high tide"), never as cause.
    - Counts, species totals, and "first" claims come verbatim from the facts.
      Never estimate, round differently, or embellish a number.
    - If unsure whether something is supported, leave it out.
    - ONLY when an item's facts line includes a "Background:" line may you add one
      detail about that species — and it must be drawn ONLY from that Background. Reach
      for the one striking or surprising thing in it (a remarkable habit or behaviour, an
      extreme — something a reader would repeat), in your own plain words, a single
      clause. If the striking fact is further down the Background, use it rather than the
      opening sentence. Skip the dull: taxonomy or classification, and size or
      resemblance to another bird. If an item has NO Background line, add NO detail about
      it — name it plainly. NEVER add a fact from your own knowledge (it may be wrong),
      never copy a source sentence, never contradict the detection data.

    STYLE:
    - Sentence case. No exclamation marks. No headings.
    - You may name a bird in English; include the Irish name in parentheses only
      for a flagged arrival (first / year-first), not for routine mentions.
    - Routine common species may be mentioned once as texture (e.g. "the usual
      sparrows and magpies"), never as a headline.
    - Return ONLY the bullets, one per line, each starting with "- ". No preamble.
  PROMPT

  # How many items to hand the model — ordered importance-first, so the tail of
  # routine tallies is bounded without hiding anything that matters.
  MAX_ITEMS = 10
  ACTIVITY_PHRASES = {
    'quieter_than_typical' => 'quieter than typical',
    'typical'              => 'typical',
    'busier_than_typical'  => 'busier than typical'
  }.freeze

  # Prompt Nova for a short Irish rendering of already-approved English bullets. Kept as a
  # translation (not a second free write) so the two languages can't disagree on the facts
  # — the English is the source of truth, the Irish tracks it.
  TRANSLATE = <<~PROMPT.freeze
    Translate these bird-station summary bullets into Irish (Gaeilge). Use the correct,
    established Irish name for each bird. Keep every number and every "first" claim exactly.
    Sentence case, no exclamation marks, no preamble. Return the SAME number of bullets, one
    per line, each starting with "- ".
  PROMPT

  # The flags that make "first"/"arrival" language truthful.
  ARRIVAL_FLAGS = %w[all_time_first all_time_first_young year_first].freeze
  # Words that assert novelty — legitimate only when the facts actually flag an arrival.
  NOVELTY = /\b(first|arriv\w+|debut|maiden|newly)\b/i
  # …but a NEGATED mention ("no new arrivals or firsts today") is not a claim — it's the
  # correct thing to say on a quiet day, so it must not trip the guard.
  NEGATION = /\b(no|not|n't|without|never|nothing|none|nor)\b/i

  class << self
    # The last-good summary for the page — bilingual { en: [...], ga: [...] }. Never
    # touches the model or blocks. The cache is only used when it's for the SAME day we're
    # rendering; a summary left over from yesterday is discarded so "today" is never stale.
    def current(facts: nil)
      facts ||= DailyFacts.for
      cached = read_cache
      return cached if cached && cached[:facts_date].to_s == facts[:date].to_s

      { bullets: DailyFacts.template_bullets(facts), source: 'template', facts_date: facts[:date], generated_at: nil }
    end

    # Regenerate and cache. Best-effort: on model failure keep the last-good cache,
    # and only synthesise a template when there is nothing cached at all.
    def refresh(now: Time.current)
      facts = DailyFacts.for(now: now, spotlight_blurb: true)
      return store(DailyFacts.template_bullets(facts), 'template', facts) if Bedrock.disabled?

      bullets = generate(facts)
      return store(bullets, 'llm', facts) if bullets
      return current(facts: facts) if valid_cache_for?(facts)

      store(DailyFacts.template_bullets(facts), 'template', facts)
    end

    # Regenerate when the cache is missing, older than max_age, OR for a previous day
    # (a new day is always stale). Cheap to call on every ingest.
    def refresh_if_stale(max_age: 15.minutes, now: Time.current)
      cached = read_cache
      fresh = cached && cached[:generated_at] && cached[:generated_at] > max_age.ago &&
              cached[:facts_date].to_s == now.to_date.to_s
      return cached if fresh

      refresh(now: now)
    end

    # Serialise the facts object into the user message. Public so a spec (or a human)
    # can eyeball exactly what the model is asked.
    def user_message(facts)
      lines = ["Date: #{facts[:date]}. #{facts[:species_today]} species, " \
               "#{facts[:detections_today]} detections today."]
      lines << 'Items (name, Irish, count, importance, flags):'
      facts[:items].first(MAX_ITEMS).each { |item| lines << item_line(item) }
      lines << "Activity: #{activity_phrase(facts[:activity_note])}." if facts[:activity_note]
      lines << spotlight_line(facts[:spotlight]) if facts[:spotlight]
      lines.join("\n")
    end

    private

    # Bilingual bullets { en:, ga: } or nil. English is generated from the facts; Irish is
    # a translation of that English, falling back to the deterministic Irish template if
    # the translation is unavailable or malformed — so a good English summary is never lost
    # to a shaky translation.
    def generate(facts)
      en = attempt(format(SYSTEM, where: station_context), user_message(facts))
      return nil unless en && supported?(en, facts)

      ga = attempt(TRANSLATE, en.map { |b| "- #{b}" }.join("\n"))
      ga = DailyFacts.template_bullets(facts)[:ga] unless ga && ga.size == en.size
      { en: en, ga: ga }
    end

    # A last-ditch factuality gate the model can't argue with: if nothing today is a first,
    # a summary that still calls something a first is wrong — reject it, take the template.
    # (When a real arrival is flagged, first-language is allowed and this passes.)
    def supported?(bullets, facts)
      return true if facts[:items].any? { |i| Array(i[:flags]).intersect?(ARRIVAL_FLAGS) }

      # Reject only an ASSERTED first — a novelty word with no negation in the same bullet.
      bullets.none? { |b| b.match?(NOVELTY) && !b.match?(NEGATION) }
    end

    # One model round-trip → validated bullets, or nil (unreachable model, or output that
    # breaks a house rule). Isolated so an Irish-translation failure never sinks the English.
    def attempt(system, user)
      bullets = parse(Bedrock.converse(system: system, user: user))
      valid?(bullets) ? bullets : nil
    rescue StandardError => e
      Rails.logger.warn("TodaySummary: LLM call failed (#{e.class}: #{e.message})")
      nil
    end

    # Model text → bullet strings. Tolerates "- ", "* " or "• " markers and drops
    # any stray preamble line.
    def parse(raw)
      raw.to_s.lines.filter_map do |line|
        text = line.strip
        next unless text.match?(/\A[-*•]\s+/)

        text.sub(/\A[-*•]\s+/, '').strip
      end
    end

    # 1–4 non-empty bullets, and none may shout — an exclamation mark is a house-rule
    # violation, so reject and let the caller keep the last-good/template instead.
    def valid?(bullets)
      bullets.size.between?(1, 4) && bullets.all?(&:present?) && bullets.none? { |b| b.include?('!') }
    end

    def item_line(item)
      irish = item[:irish_name].present? ? " (#{item[:irish_name]})" : ''
      flags = item[:flags].join(', ')
      line = "- #{item[:common_name]}#{irish}, #{item[:call_count]}, importance #{item[:importance]}, [#{flags}]"
      line += "\n  Background (#{item[:common_name]}): #{item[:blurb]}" if item[:blurb].present?
      line
    end

    def spotlight_line(spotlight)
      line = "Spotlight: #{spotlight[:common_name]} — #{spotlight[:rarity_context]}."
      line += " Background: #{spotlight[:blurb]}" if spotlight[:blurb].present?
      line
    end

    def activity_phrase(note)
      ACTIVITY_PHRASES.fetch(note.to_s, note.to_s.tr('_', ' '))
    end

    # The station's location for the prompt, from config/API (Station) — never a
    # literal place name in code. Empty when unconfigured.
    def station_context
      Station.region.present? ? " in #{Station.region}" : ''
    end

    # Is there a cache, and is it for the day we're about to render? Guards refresh's
    # keep-last-good path so a generation failure never resurrects yesterday's summary.
    def valid_cache_for?(facts)
      cached = read_cache
      cached.present? && cached[:facts_date].to_s == facts[:date].to_s
    end

    def read_cache
      return nil unless STORE.exist?

      data = JSON.parse(STORE.read, symbolize_names: true)
      # Bilingual shape only — a legacy flat-array cache (pre-bilingual) is treated as
      # absent, so it's discarded rather than shown monolingual.
      bullets = data[:bullets]
      return nil unless bullets.is_a?(Hash)

      en = Array(bullets[:en]).compact_blank
      return nil if en.empty?

      ga = Array(bullets[:ga]).compact_blank.presence || en
      { bullets: { en: en, ga: ga }, source: data[:source],
        facts_date: data[:facts_date], generated_at: safe_time(data[:generated_at]) }
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def store(bullets, source, facts)
      data = { bullets: bullets, source: source, facts_date: facts[:date],
               generated_at: Time.current.iso8601 }
      tmp = STORE.sub_ext('.tmp')
      tmp.write(JSON.pretty_generate(data))
      tmp.rename(STORE.to_s) # atomic replace so a reader never sees a half-written file
      { bullets: bullets, source: source, facts_date: facts[:date], generated_at: safe_time(data[:generated_at]) }
    end

    def safe_time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
