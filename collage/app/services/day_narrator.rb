# Narrates a single day into 2–4 warm, factual bullets that read like a naturalist's diary
# entry, not a stats readout. Given a DailyFacts hash for ANY day (today, or a completed past
# day for the Journal), it returns bilingual bullets + their source + the citations behind the
# facts & folklore. Ruby has already done the reasoning (DailyFacts for the day's shape;
# EnrichmentBundle for each prominent bird's already-sourced facts & folklore); this layer only
# asks the model to STITCH that material, and falls back to a rich no-model version when the
# model is unavailable. It is date-agnostic and stateless: TodaySummary wraps it with the
# today cache, JournalEntry wraps it with a frozen per-day store.
class DayNarrator
  # Verbatim from today_summary_prompt.md — the factual rules are absolute and the
  # narration is only trustworthy because these travel with the request. The location is
  # not hard-coded: `%<where>s` is filled from Station (config/API).
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
    - If a bird has NO entry in that material — including a brand-new arrival — name it and
      report the plain event (that it was logged, its count), and say NOTHING characterising
      about it. Do NOT reach into your own knowledge for its behaviour, folklore, symbolism,
      or status, not even hedged ("often said to…", "has carried symbolic weight"). Better a
      bare, true line than an invented one.
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
  LORE_SPECIES = 5
  # How many un-enriched NOTABLE birds a single pass will source on the spot.
  ENRICH_ON_REFRESH = 3
  ACTIVITY_PHRASES = {
    'quieter_than_typical' => 'quieter than typical',
    'typical'              => 'typical',
    'busier_than_typical'  => 'busier than typical'
  }.freeze

  # Prompt for a short Irish rendering of already-approved English bullets. Kept as a
  # translation (not a second free write) so the two languages can't disagree on the facts.
  TRANSLATE = <<~PROMPT.freeze
    Translate these bird-station summary bullets into Irish (Gaeilge). Use the correct,
    established Irish name for each bird. Keep every number and every "first" claim exactly.
    Keep the **double asterisks** around every bird name, wrapping the IRISH name in them
    (e.g. **house sparrow** becomes **gealbhán binne**). Where the English gives a bird as
    "Common Name (Irish name)", use ONLY the Irish name in Irish — do NOT repeat it in
    parentheses. Sentence case, no exclamation marks, no preamble. Return the SAME number of
    bullets, one per line, each starting with "- ".
  PROMPT

  # The flags that make "first"/"arrival" language truthful.
  ARRIVAL_FLAGS = %w[all_time_first all_time_first_young year_first].freeze
  # Words that assert novelty — legitimate only when the facts actually flag an arrival.
  NOVELTY = /\b(first|arriv\w+|debut|maiden|newly)\b/i
  # …but a NEGATED mention ("no new arrivals or firsts today") is not a claim.
  NEGATION = /\b(no|not|n't|without|never|nothing|none|nor)\b/i

  # The daily voice is the most-read, most-embarrassing-if-wrong text in the app, so it
  # narrates and translates with the stronger Claude model (the enrichment model), not Nova
  # Lite (which conflated importance with loudness and mangled the Gaeilge). A lambda so an
  # ENRICH_MODEL_ID override is picked up at call time, not load time.
  NARRATOR_MODEL = -> { Bedrock.enrich_model_id }
  NARRATOR_TOKENS = 700
  # The dry, encyclopedic kind of fact the no-model fallback skips in favour of a
  # behaviour/voice/habit fact or folklore. Single stems only (no literal spaces).
  DULL_FACT = /\b(identif|resembl|distinguish|plumage|juvenile|eyes?|feather|widely|
                  distribut|inhabit|habitat|taxonom|subspecies|measur|weigh|wingspan|centimet)/ix
  # Flags the no-model fallback treats as genuine news (a real first). all_time_first_young
  # is deliberately excluded — in a young station everything is a "first", so it's damped.
  NEWS_FLAGS = %w[all_time_first year_first].freeze
  NEWS_LABEL = {
    en: { all_time_first: 'New for the station', year_first: 'First of the year' },
    ga: { all_time_first: 'Nua ag an stáisiún', year_first: 'Céaduair i mbliana' }
  }.freeze
  # Appended when narrating a COMPLETED past day (the Journal), so the finished day reads in
  # retrospect — "today"/"so far" belong only to the in-progress day the front page shows.
  COMPLETED_DAY_NOTE = 'This entry is for a COMPLETED day (the Date above), written in ' \
                       'retrospect. Use the PAST TENSE throughout — "led the day", "was heard", ' \
                       '"arrived". Do NOT write "today" or "so far"; the day is finished.'.freeze

  class << self
    # Narrate a day → { bullets: { en:, ga: }, source: 'llm'|'facts'|'template', sources: [...] }.
    # Stateless and date-agnostic — the caller decides how to cache/freeze it.
    #   model:  false → skip the model entirely, return the rich fallback (the never-block path)
    #   enrich: true  → source the day's un-enriched notable birds first (slow; the build path)
    # 'llm' means the model wrote it; 'facts'/'template' mean it fell back (model off/failed).
    def narrate(facts, model: true, enrich: false)
      ensure_notable_enriched(facts) if enrich && model
      lore = enrichment_for(facts)
      sources = sources_from(lore)
      if model && !Bedrock.disabled? && (bullets = generate(facts, lore))
        return { bullets: bullets, source: 'llm', sources: sources }
      end

      bullets, source = fallback(facts, lore)
      { bullets: bullets, source: source, sources: sources }
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
    # deterministic Irish template if the translation is unavailable or malformed.
    def generate(facts, lore = [])
      message = user_message(facts, lore)
      message = "#{message}\n\n#{COMPLETED_DAY_NOTE}" if completed_day?(facts)
      en = attempt(format(SYSTEM, where: station_context), message)
      return nil unless en && supported?(en, facts)

      ga = attempt(TRANSLATE, en.map { |b| "- #{b}" }.join("\n"))
      ga = DailyFacts.template_bullets(facts)[:ga] unless ga && ga.size == en.size
      { en: en, ga: ga }
    end

    # Source the day's NOTABLE birds NOW if they lack a bundle — an arrival or a rarity is the
    # highest-priority thing to have real, cited lore for. Cached + durable → a one-time cost
    # per new bird. Capped and best-effort: a failure just leaves that bird un-enriched.
    def ensure_notable_enriched(facts)
      return if Bedrock.disabled?

      due = Array(facts[:notable_today]).
            reject { |i| EnrichmentBundle.current(i[:sci_name])&.block_objects&.any? }.
            first(ENRICH_ON_REFRESH)
      due.each do |item|
        Enrichment::Builder.build_one(date: Date.parse(facts[:date].to_s), sci_name: item[:sci_name],
                                      common_name: item[:common_name], irish_name: item[:irish_name])
      rescue StandardError => e
        Rails.logger.warn("DayNarrator: enrich #{item[:sci_name]} failed (#{e.class}: #{e.message})")
      end
    end

    # The distinct citations behind the material fed to the note — { host:, url: } pairs.
    def sources_from(lore)
      Array(lore).flat_map { |bird| Array(bird[:blocks]) }.
        flat_map { |block| Array(block[:sources]) }.
        filter_map { |s| { host: s[:host], url: s[:url] } if s[:url].present? }.uniq
    end

    # The stored facts & folklore for the day's most prominent species — a pure DB read of
    # the latest EnrichmentBundle per species (durable across days), so nothing is fetched.
    def enrichment_for(facts)
      items = Array(facts[:items])
      prominent = (items.first(LORE_SPECIES) + [items.max_by { |i| i[:call_count] }]).
                  compact.uniq { |i| i[:sci_name] }
      bundles = EnrichmentBundle.current_for(prominent.pluck(:sci_name)).index_by(&:sci_name)
      prominent.filter_map do |item|
        display = bundles[item[:sci_name]]&.to_display
        next unless display

        { common_name: item[:common_name], irish_name: item[:irish_name], blocks: display[:blocks] }
      end
    end

    # The no-LLM fallback — [bullets, source]. Deliberately BIRD CHARACTER, not a recap: the
    # day's genuine news (a named all-time/year first) then a striking fact or folklore about
    # each prominent enriched bird, verbatim from the vetted bundles. The counts / "most heard"
    # / activity lines are left OUT. Shown as 'facts'; falls to the bare 'template' (hidden)
    # only when there is genuinely nothing to say.
    def fallback(facts, lore)
      news = news_bullets(facts)
      character = character_bullets(lore)
      en = (news[:en] + character[:en]).first(4)
      ga = (news[:ga] + character[:ga]).first(4)
      return [{ en: en, ga: ga }, 'facts'] if en.any?

      [DailyFacts.template_bullets(facts), 'template']
    end

    # Today's genuine news as bilingual bullets — an all-time or year first, named.
    def news_bullets(facts)
      arrivals = Array(facts[:items]).select { |i| Array(i[:flags]).intersect?(NEWS_FLAGS) }.first(2)
      { en: arrivals.map { |i| news_line(i, :en) }, ga: arrivals.map { |i| news_line(i, :ga) } }
    end

    def news_line(item, lang)
      kind = Array(item[:flags]).include?('year_first') ? :year_first : :all_time_first
      name = lang == :ga ? item[:irish_name].presence || item[:common_name] : item[:common_name]
      "#{NEWS_LABEL[lang][kind]}: #{name}."
    end

    # A genuinely interesting thing about the day's birds — a behaviour/habit fact or a piece
    # of folklore — scanning ALL the prominent enriched birds and taking the best three.
    def character_bullets(lore)
      picked = Array(lore).filter_map { |bird| interesting_block(bird[:blocks]) }.first(3)
      { en: picked.pluck(:text), ga: picked.map { |b| b[:text_ga].presence || b[:text] } }
    end

    def interesting_block(blocks)
      vivid_fact(blocks) || folklore(blocks)
    end

    def vivid_fact(blocks)
      blocks.find { |b| b[:type] == 'fact' && !b[:text].to_s.match?(DULL_FACT) }
    end

    def folklore(blocks)
      blocks.find { |b| b[:type] == 'folklore' }
    end

    # Render the stored lore into the prompt: each prominent bird, then its typed blocks.
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

    # A last-ditch factuality gate: if nothing today is a first, a summary that still calls
    # something a first is wrong — reject it, take the fallback.
    def supported?(bullets, facts)
      return true if facts[:items].any? { |i| Array(i[:flags]).intersect?(ARRIVAL_FLAGS) }

      bullets.none? { |b| b.match?(NOVELTY) && !b.match?(NEGATION) }
    end

    # One model round-trip → validated bullets, or nil (unreachable model, or output that
    # breaks a house rule). Isolated so an Irish-translation failure never sinks the English.
    def attempt(system, user)
      bullets = parse(Bedrock.converse(system: system, user: user,
                                       model_id: NARRATOR_MODEL.call, max_tokens: NARRATOR_TOKENS))
      valid?(bullets) ? bullets : nil
    rescue StandardError => e
      Rails.logger.warn("DayNarrator: LLM call failed (#{e.class}: #{e.message})")
      nil
    end

    # Model text → bullet strings. Tolerates "- ", "* " or "• " markers and drops preamble.
    def parse(raw)
      raw.to_s.lines.filter_map do |line|
        text = line.strip
        next unless text.match?(/\A[-*•]\s+/)

        text.sub(/\A[-*•]\s+/, '').strip
      end
    end

    # 1–4 non-empty bullets, none shouting (an exclamation mark is a house-rule violation).
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

    # A day is "completed" (a Journal entry) when its date is before today — the front page's
    # in-progress day is not. Drives the past-tense framing.
    def completed_day?(facts)
      date = facts[:date].to_s
      date.present? && date < Date.current.iso8601
    end

    # The station's location for the prompt, from config/API (Station) — never a literal.
    def station_context
      Station.region.present? ? " in #{Station.region}" : ''
    end
  end
end
