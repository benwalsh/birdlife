require 'json'

# The home page's daily "today" note — 2–4 warm, factual bullets that read like a
# naturalist's diary entry, not a stats readout. Ruby does all the reasoning (DailyFacts
# for the day's shape; EnrichmentBundle for each prominent bird's already-sourced facts &
# folklore); this layer only asks the model to STITCH that material — the day woven around
# a striking thing or two about the birds heard — then caches the result to disk. No live
# dúchas/Wikipedia lookup happens here: the sourcing already ran in the enrichment pass, so
# a refresh is a single cheap model call.
#
# The page never blocks on the model: it always reads the last-good cache (`current`). A
# scheduled/lazy `refresh` regenerates (~30-min cache). If the model is unreachable the
# last-good summary stays; only when there is no cache at all do we fall through to the
# deterministic, always-correct template. So warmth never costs accuracy or availability.
class TodaySummary
  STORE = Rails.root.join('storage/today_summary.json')

  # Verbatim from today_summary_prompt.md — the factual rules are absolute and the
  # summary layer is only trustworthy because these travel with the request. The
  # location is not hard-coded: `%<where>s` is filled from Station (config/API).
  SYSTEM = <<~PROMPT.freeze
    You write the daily "today" note for a bird-listening station%<where>s. It detects
    birds by sound and logs them. Your note is a short naturalist's diary entry — warm,
    specific, and about the BIRDS themselves, not a statistics readout.

    Write 2 to 4 short bullets. The SUBSTANCE of the note is what is interesting about the
    day's birds: a vivid fact or a piece of folklore about one or two of the day's
    prominent species, drawn ONLY from the "About the birds" material below. The day's
    numbers (totals, the most-detected species, quieter/busier) are texture you weave
    AROUND those facts — never the headline, and never a bare "N species and N detections
    logged today, most heard X, Y, Z" recap. That flat recap is exactly what NOT to write;
    a note that is only counts has failed.

    Lead with genuine news when there is any: an all-time first or a year-first is what a
    reader most wants to know, so feature it (with the Irish name in parentheses). On an
    ordinary day with no arrivals, lead instead with the most characterful bird of the day
    and something true and striking about it, then let the rest of the day follow.

    USING THE "About the birds" MATERIAL:
    - It is the ONLY source of characterising detail you may state about a species. Never
      add a fact from your own knowledge — it may be wrong.
    - Reach for the one surprising, repeatable thing (a remarkable habit, a voice, an
      extreme). Put it in your own plain words; do not copy a source sentence. Skip the
      dull — taxonomy, size, what it resembles.
    - A [folklore] item is LORE, not fact — frame it as such ("in Irish tradition…", "old
      lore held…"), never as something the bird actually does.
    - Connect a fact to the day where it reads naturally ("the herring gull led the day at
      203 — a bird that will …"), but don't force every bird to carry one.

    TONE: warm but understated. A quiet rural station, not a nature documentary. Restraint
    over enthusiasm.

    FACTUAL RULES — these are absolute:
    - State ONLY what is given — the facts, or the About-the-birds material. Every clause
      traces to something given.
    - Do NOT invent or imply bird behaviour, migration, motivation, origin, or destination
      beyond what the material states. Do NOT link birds to weather, wind, temperature, or
      sky. The station cannot observe why a bird was heard.
    - Tide may be mentioned ONLY for an item carrying a tide phase field, ONLY as
      co-occurrence, never as cause.
    - Counts, species totals, and "first" claims come verbatim from the facts. Never
      estimate, round differently, or embellish a number.
    - The items are listed in IMPORTANCE order, which is NOT count order. Only the single
      species on the "Most detected today by count" line is the most heard / most detected;
      never attach that superlative to any other species. Give every other species its
      actual number.
    - unusual_volume_high means that species was heard MORE than its usual daily amount;
      unusual_volume_low means FEWER. Never say a bird was busier or above normal when its
      flag is unusual_volume_low — that is backwards.
    - A species is a "first" ONLY if its line carries an all_time_first or year_first flag.
      If nothing is flagged, call nothing a first or new arrival.
    - If unsure whether something is supported, leave it out.

    STYLE:
    - Sentence case. No exclamation marks. No headings.
    - Name a bird in English; add the Irish name in parentheses for a flagged arrival, and
      you may add it once for the bird a folklore line is about.
    - Wrap EVERY bird name in **double asterisks** each time it appears — English or Irish,
      e.g. **house sparrow**, **cág cosdearg** — so the page can set the species name apart.
    - Return ONLY the bullets, one per line, each starting with "- ". No preamble.
  PROMPT

  # How many items to hand the model — ordered importance-first, so the tail of
  # routine tallies is bounded without hiding anything that matters.
  MAX_ITEMS = 10
  # How many of the day's most prominent species to pull stored facts & folklore for.
  # These are the birds the note can characterise; the summariser weaves one or two of
  # their striking blocks in. A pure DB read (EnrichmentBundle) — no dúchas/Wikipedia
  # lookup at summary time; the sourcing already happened in the enrichment pass.
  LORE_SPECIES = 5
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
    Keep the **double asterisks** around every bird name, wrapping the IRISH name in them
    (e.g. **house sparrow** becomes **gealbhán binne**). Sentence case, no exclamation marks,
    no preamble. Return the SAME number of bullets, one per line, each starting with "- ".
  PROMPT

  # The flags that make "first"/"arrival" language truthful.
  ARRIVAL_FLAGS = %w[all_time_first all_time_first_young year_first].freeze
  # Words that assert novelty — legitimate only when the facts actually flag an arrival.
  NOVELTY = /\b(first|arriv\w+|debut|maiden|newly)\b/i
  # …but a NEGATED mention ("no new arrivals or firsts today") is not a claim — it's the
  # correct thing to say on a quiet day, so it must not trip the guard.
  NEGATION = /\b(no|not|n't|without|never|nothing|none|nor)\b/i

  # The front page's daily voice is the most-read, most-embarrassing-if-wrong text in the
  # app, and it must hold a strict factual line (importance vs count, direction of a
  # volume anomaly, no invented behaviour, correct Irish). Nova Lite proved too loose — it
  # conflated the importance-led species with the loudest and mangled the Gaeilge — so the
  # today summary narrates and translates with the stronger Claude model (the same one the
  # enrichment sourcing pass uses). A handful of short calls an hour; the quality is worth
  # it. A lambda so an ENRICH_MODEL_ID override is picked up at call time, not load time.
  NARRATOR_MODEL = -> { Bedrock.enrich_model_id }
  NARRATOR_TOKENS = 700
  # The dry, encyclopedic kind of fact — identification, plumage, size, range, taxonomy —
  # that reads as filler. The no-model fallback skips these in favour of a behaviour/voice/
  # habit fact, or folklore, so the bird-character it shows is the interesting stuff. Single
  # stems only (no literal spaces — the /x flag would swallow them), no trailing boundary so
  # "distribut" catches "distributed", "measur" catches "measures", etc.
  DULL_FACT = /\b(identif|resembl|distinguish|plumage|juvenile|eyes?|feather|widely|
                  distribut|inhabit|habitat|taxonom|subspecies|measur|weigh|wingspan|centimet)/ix
  # Flags the no-model fallback treats as genuine news (a real first). all_time_first_young
  # is deliberately excluded — in a young station everything is a "first", so it's damped.
  NEWS_FLAGS = %w[all_time_first year_first].freeze
  NEWS_LABEL = {
    en: { all_time_first: 'New for the station', year_first: 'First of the year' },
    ga: { all_time_first: 'Nua ag an stáisiún', year_first: 'Céaduair i mbliana' }
  }.freeze

  class << self
    # The last-good summary for the page — bilingual { en: [...], ga: [...] }. Never
    # touches the model or blocks. The cache is only used when it's for the SAME day we're
    # rendering; a summary left over from yesterday is discarded so "today" is never stale.
    def current(facts: nil)
      facts ||= DailyFacts.for
      cached = read_cache
      return cached if cached && cached[:facts_date].to_s == facts[:date].to_s

      bullets, source = fallback(facts, enrichment_for(facts))
      { bullets: bullets, source: source, facts_date: facts[:date], generated_at: nil }
    end

    # Regenerate and cache. Best-effort: on model failure keep the last-good cache,
    # and only synthesise a template when there is nothing cached at all. The facts are
    # a pure DB read (no spotlight_blurb → no Wikipedia hop); the bird-character material
    # comes from the stored enrichment bundles, so a refresh does no live sourcing —
    # just one model call to stitch already-gathered facts & folklore into the day.
    def refresh(now: Time.current)
      facts = DailyFacts.for(now: now)
      lore = enrichment_for(facts)
      return store(*fallback(facts, lore), facts) if Bedrock.disabled?

      bullets = generate(facts, lore)
      return store(bullets, 'llm', facts) if bullets
      return current(facts: facts) if valid_cache_for?(facts)

      store(*fallback(facts, lore), facts)
    end

    # Regenerate when the cache is missing, older than max_age, OR for a previous day
    # (a new day is always stale). Cheap to call on every ingest. Half an hour keeps the
    # note fresh without re-stitching on every load — the stored facts change slowly.
    def refresh_if_stale(max_age: 30.minutes, now: Time.current)
      cached = read_cache
      fresh = cached && cached[:generated_at] && cached[:generated_at] > max_age.ago &&
              cached[:facts_date].to_s == now.to_date.to_s
      return cached if fresh

      refresh(now: now)
    end

    # Serialise the facts object + stored bird-lore into the user message. Public so a
    # spec (or a human) can eyeball exactly what the model is asked. `lore` is the shape
    # returned by enrichment_for: an array of { common_name:, irish_name:, blocks: }.
    def user_message(facts, lore = [])
      lines = ["Date: #{facts[:date]}. #{facts[:species_today]} species, " \
               "#{facts[:detections_today]} detections today."]
      if (loudest = facts[:items].max_by { |i| i[:call_count] })
        lines << "Most detected today by count: #{loudest[:common_name]} (#{loudest[:call_count]})."
      end
      lines << 'Items (name, Irish, count, importance, flags) — IMPORTANCE order, not count order:'
      facts[:items].first(MAX_ITEMS).each { |item| lines << item_line(item) }
      lines << "Activity: #{activity_phrase(facts[:activity_note])}." if facts[:activity_note]
      lines << spotlight_line(facts[:spotlight]) if facts[:spotlight]
      lines.concat(lore_lines(lore))
      lines.join("\n")
    end

    private

    # Bilingual bullets { en:, ga: } or nil. English is generated from the facts + the
    # stored bird-lore; Irish is a translation of that English, falling back to the
    # deterministic Irish template if the translation is unavailable or malformed — so a
    # good English summary is never lost to a shaky translation.
    def generate(facts, lore = [])
      en = attempt(format(SYSTEM, where: station_context), user_message(facts, lore))
      return nil unless en && supported?(en, facts)

      ga = attempt(TRANSLATE, en.map { |b| "- #{b}" }.join("\n"))
      ga = DailyFacts.template_bullets(facts)[:ga] unless ga && ga.size == en.size
      { en: en, ga: ga }
    end

    # The stored facts & folklore for the day's most prominent species — the material the
    # note characterises the day with. A pure DB read of the latest EnrichmentBundle per
    # species (durable across days), so nothing is fetched here. Empty when no prominent
    # bird has been enriched yet (the note then leans on the day's shape alone).
    def enrichment_for(facts)
      items = Array(facts[:items])
      # The prominent birds: the top few by importance PLUS the single loudest — the
      # most-detected bird can sit low in importance order (a common resident heard all
      # day), yet it's the one the note most wants something to say about.
      prominent = (items.first(LORE_SPECIES) + [items.max_by { |i| i[:call_count] }]).
                  compact.uniq { |i| i[:sci_name] }
      bundles = EnrichmentBundle.current_for(prominent.pluck(:sci_name)).index_by(&:sci_name)
      prominent.filter_map do |item|
        display = bundles[item[:sci_name]]&.to_display
        next unless display

        { common_name: item[:common_name], irish_name: item[:irish_name], blocks: display[:blocks] }
      end
    end

    # The no-LLM fallback — returned as [bullets, source]. This is what shows whenever
    # Bedrock can't be reached (a new day before the timer runs, a lapsed SSO session, an
    # outage), which locally is most of the time — so it must NOT be the bare tally. It is
    # deliberately BIRD CHARACTER, not a recap: the day's genuine news (an all-time / year
    # first, named) followed by a striking fact or piece of folklore about each of the day's
    # most prominent enriched birds — verbatim from the vetted bundles. The counts, the
    # "most heard" line, the activity note — the lines that read as dumbed-down — are
    # deliberately left OUT. Shown as 'facts'. Only when there is genuinely nothing to say
    # (no news, nothing enriched) does it fall to the bare template ('template', hidden).
    def fallback(facts, lore)
      news = news_bullets(facts)
      character = character_bullets(lore)
      en = (news[:en] + character[:en]).first(4)
      ga = (news[:ga] + character[:ga]).first(4)
      return [{ en: en, ga: ga }, 'facts'] if en.any?

      [DailyFacts.template_bullets(facts), 'template']
    end

    # Today's genuine news as bilingual bullets — an all-time or year first, named. NOT the
    # counts and NOT "most heard": those bare-recap lines are exactly what we keep out.
    def news_bullets(facts)
      arrivals = Array(facts[:items]).select { |i| Array(i[:flags]).intersect?(NEWS_FLAGS) }.first(2)
      { en: arrivals.map { |i| news_line(i, :en) }, ga: arrivals.map { |i| news_line(i, :ga) } }
    end

    def news_line(item, lang)
      kind = Array(item[:flags]).include?('year_first') ? :year_first : :all_time_first
      name = lang == :ga ? item[:irish_name].presence || item[:common_name] : item[:common_name]
      "#{NEWS_LABEL[lang][kind]}: #{name}."
    end

    # A genuinely interesting thing about the day's birds — a behaviour/habit fact or a
    # piece of folklore — scanning ALL the prominent enriched birds and taking the best
    # three. A bird whose bundle holds only dry identification/range facts is SKIPPED, not
    # padded in: better two lines that sing than four with filler.
    def character_bullets(lore)
      picked = Array(lore).filter_map { |bird| interesting_block(bird[:blocks]) }.first(3)
      { en: picked.pluck(:text), ga: picked.map { |b| b[:text_ga].presence || b[:text] } }
    end

    # The interesting block for a bird — a non-dry fact, else folklore. Nil when the bird
    # only has dry facts (so it's left out rather than dragging the note down).
    def interesting_block(blocks)
      vivid_fact(blocks) || folklore(blocks)
    end

    # A fact worth leading with — the first behaviour/habit/voice fact, i.e. not one of the
    # dry identification/size notes. Nil when the bird only has dry facts (so the caller can
    # reach for folklore instead).
    def vivid_fact(blocks)
      blocks.find { |b| b[:type] == 'fact' && !b[:text].to_s.match?(DULL_FACT) }
    end

    def folklore(blocks)
      blocks.find { |b| b[:type] == 'folklore' }
    end

    # Render the stored lore into the prompt: each prominent bird, then its typed blocks.
    # The [type] tag lets the writer treat [folklore] as lore and [fact]/[regional_note]
    # as fact, per the prompt's rules.
    def lore_lines(lore)
      return [] if lore.blank?

      lines = ['About the birds (the ONLY characterising detail you may state — weave one ' \
               'or two striking things in; [folklore] is lore, not fact):']
      lore.each do |bird|
        irish = bird[:irish_name].present? ? " (#{bird[:irish_name]})" : ''
        lines << "#{bird[:common_name]}#{irish}:"
        bird[:blocks].each { |block| lines << "  - [#{block[:type]}] #{block[:text]}" }
      end
      lines
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
      bullets = parse(Bedrock.converse(system: system, user: user,
                                       model_id: NARRATOR_MODEL.call, max_tokens: NARRATOR_TOKENS))
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
