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
    - Each flagged arrival (a first / year-first) is followed by a Background line
      about THAT species (an encyclopedia extract). For an arrival, WEAVE IN one
      genuinely INTERESTING detail drawn from its OWN Background — reach for the
      striking or surprising: a remarkable habit or behaviour, an extreme, something a
      reader would repeat to someone else. (For example: that swifts eat, sleep and
      even mate on the wing and almost never land; that a cuckoo lays its eggs in other
      birds' nests for them to raise.) In your own plain words, a single clause.
      AVOID the dull — these are NOT interesting and must never be your detail:
      taxonomy or classification ("a member of the order Cuculiformes", "a passerine"),
      and size or resemblance to another bird ("similar to a swallow but larger",
      "a medium-sized bird"). If the striking fact is further down the Background, use
      it — do not default to the first sentence. Use ONLY the Background; NEVER add a
      fact from your own memory (it may be wrong); never copy its sentences; never
      contradict the detection data. If the Background genuinely offers nothing striking,
      name the bird plainly with no filler detail.

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

  class << self
    # The last-good summary for the page. Never touches the model or blocks. Pass
    # `facts:` (the caller usually already built them) to skip a rebuild on a cache
    # miss; otherwise a fresh DailyFacts is computed for the template.
    def current(facts: nil)
      cached = read_cache
      return cached if cached

      facts ||= DailyFacts.for
      { bullets: DailyFacts.template_bullets(facts), source: 'template', generated_at: nil }
    end

    # Regenerate and cache. Best-effort: on model failure keep the last-good cache,
    # and only synthesise a template when there is nothing cached at all.
    def refresh(now: Time.current)
      facts = DailyFacts.for(now: now, spotlight_blurb: true)
      return store(DailyFacts.template_bullets(facts), 'template', facts) if Bedrock.disabled?

      bullets = generate(facts)
      return store(bullets, 'llm', facts) if bullets
      return current if STORE.exist?

      store(DailyFacts.template_bullets(facts), 'template', facts)
    end

    # Regenerate only when the cache is missing or older than max_age. Cheap to call
    # on every ingest — the cloud's trigger for a fresh summary as new data lands,
    # without a Bedrock hit on each push.
    def refresh_if_stale(max_age: 15.minutes, now: Time.current)
      cached = read_cache
      return cached if cached && cached[:generated_at] && cached[:generated_at] > max_age.ago

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

    def generate(facts)
      raw = Bedrock.converse(system: format(SYSTEM, where: station_context), user: user_message(facts))
      bullets = parse(raw)
      valid?(bullets) ? bullets : nil
    rescue StandardError => e
      Rails.logger.warn("TodaySummary: LLM generation failed (#{e.class}: #{e.message})")
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

    def read_cache
      return nil unless STORE.exist?

      data = JSON.parse(STORE.read, symbolize_names: true)
      bullets = Array(data[:bullets]).compact_blank
      return nil if bullets.empty?

      { bullets: bullets, source: data[:source], generated_at: safe_time(data[:generated_at]) }
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def store(bullets, source, facts)
      data = { bullets: bullets, source: source, facts_date: facts[:date],
               generated_at: Time.current.iso8601 }
      tmp = STORE.sub_ext('.tmp')
      tmp.write(JSON.pretty_generate(data))
      tmp.rename(STORE.to_s) # atomic replace so a reader never sees a half-written file
      { bullets: bullets, source: source, generated_at: safe_time(data[:generated_at]) }
    end

    def safe_time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
