require 'securerandom'

module Enrichment
  # Stage 1 of the enrichment pipeline: the SOURCING pass. For a notable species it
  # runs Claude (Bedrock Converse tool-use) with exactly one tool — SourceFetcher —
  # and asks it to read trusted ornithological / heritage pages and return a short set
  # of typed, cited blocks (a general fact, a regional note, a piece of folklore). The
  # result is stored once per (sci_name, date) as an EnrichmentBundle, so a single
  # lookup serves every subscriber's Assembler.
  #
  # Integrity is enforced, not trusted: a block survives only if it validates AND every
  # citation it carries was a URL we actually fetched this run (logged in
  # source_fetch_log). A fabricated citation is dropped; a block left with none is
  # dropped with it. "Ruby computes, Claude sources, and nothing unsourced ships."
  class Builder
    # Navigating the dúchas search → story pages costs fetches, so the loop needs headroom
    # to do that AND still secure a folklore block (falling back to Wikipedia) — 8 left it
    # exhausting the budget on the archives and finalising with none.
    MAX_ROUNDS = 12
    MAX_FETCH_CHARS = 6000
    # On a day with nothing notable, still source this many of the most interesting DUE
    # species — the floor that keeps a quiet/young station building a facts & folklore
    # library instead of sourcing nothing. 0 restores the old notable-only behaviour.
    DAILY_FLOOR = Integer(ENV.fetch('ENRICH_DAILY_FLOOR', 1))
    # When research runs long, this forces the model to stop and answer from what it has
    # already fetched, so a thorough explorer still yields blocks instead of nothing.
    FINALISE = 'Stop searching now. Using ONLY the sources you have already fetched ' \
               'successfully, output the JSON array of blocks and nothing else. Include a ' \
               'folklore block if any source you fetched supports one (e.g. a Wikipedia ' \
               'mythology/folklore section) — do not omit folklore just because the Irish ' \
               'archives were thin.'.freeze

    FETCH_TOOL = {
      tool_spec: {
        name:         'fetch_source',
        description:  'Fetch the readable text of a page on a trusted ornithological or ' \
                      'Irish-heritage host (e.g. en.wikipedia.org, birdwatchireland.ie, ' \
                      'duchas.ie). Returns plain text to read and cite, or an error if the ' \
                      'host is not trusted or the page cannot be read. This is the only way ' \
                      'to see a source; never cite a URL you have not fetched here.',
        input_schema: { json: {
          type:       'object',
          properties: { url: { type: 'string', description: 'Full https:// URL on a trusted host.' } },
          required:   ['url']
        } }
      }
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You are the daily researcher for a bird-listening station at %<place>s. Once a day you
      research one species and save a small set of true, well-sourced blocks that a separate
      writer will later stitch into readers' notes. You do the research; nobody downstream
      does any. You may ONLY use the fetch_source tool to learn anything — you have no
      knowledge of your own that you are allowed to state.

      Choosing sources by block type:
        - FACT: Wikipedia (en.wikipedia.org) is reliable and deep — use it freely for the
          general behaviour/voice/habit facts.
        - REGIONAL_NOTE: prefer the IRISH birding sources — BirdWatch Ireland
          (birdwatchireland.ie and its county branches), irishbirding.com, the Irish Rare
          Birds Committee (irbc.ie), the Irish Wildlife Trust (iwt.ie), the National
          Biodiversity Data Centre (biodiversityireland.ie). This is the LOCAL angle (its
          status in Ireland, where near here it turns up, an Irish-name meaning); an Irish
          source is worth far more than a generic Wikipedia line. For a scarce bird or a
          vagrant especially, irishbirding.com / irbc.ie carry the Irish records.
        - FOLKLORE: dúchas.ie is the FAVOURITE — clearly prefer it to Wikipedia. Search the
          Schools' Collection ONCE: fetch https://www.duchas.ie/en/cbes?Search=TERM (use the
          bird's Irish name, e.g. its name in the task, and/or English). The result ends
          with a "LINKS" list; FOLLOW one promising /en/cbes/<id>/<id> story link — that
          returns the clean transcribed text, and you may quote or closely retell a FULL
          short story (folklore blocks can run long; that's wanted, not a snippet). A story
          can carry over pages — a page fetch ends with an "ENTRIES" list, so fetch the entry
          (story) URL for the whole story rather than a page fragment. Cite the /en/cbes/ URL
          you fetched. celt.ucc.ie is a second Irish option. Be economical —
          dúchas rate-limits, so one search and one or two story fetches, not a dozen. ONLY
          if dúchas and CELT genuinely have nothing for this bird, fall back to Wikipedia's
          folklore/mythology (e.g. the crow-goddess Badb) rather than returning none.
      A few good sources beat a long hunt. Fetch what you need, then return the blocks.

      Return up to 12 blocks as a JSON array and NOTHING else — no prose, no code fence.
      Each block is an object:
        { "type": "fact" | "regional_note" | "folklore",
          "id": "short-kebab-id",
          "text": "one or two plain sentences",
          "text_ga": "the SAME sentences in natural, idiomatic Irish (Gaeilge)",
          "sources": [ { "host": "en.wikipedia.org", "url": "https://..." } ],
          "gated": false }

      Build a small LIBRARY for this species — enough that a writer stitching a note has
      variety to draw on across many days, never the same line twice. Aim, where the
      sources support it, for roughly: SEVERAL facts (say 6–8, each a DISTINCT thing —
      don't restate one fact five ways), ONE or TWO regional notes, and ONE or TWO
      folklore pieces. A Wikipedia article alone usually yields several good facts from a
      single fetch. Quality still gates quantity: a vivid, solid block beats a dull or
      shaky one, and it's fine to return fewer if that's all the sources truly support.
        fact          — a vivid, memorable thing about the species: a striking behaviour,
                        its voice, how it feeds or nests, migration, longevity, a naming
                        quirk, an extreme. Reach for what would make a listener look up, NOT
                        its length and weight. Skip bare measurements. Each fact block must
                        stand on its own — a different idea from the others.
        regional_note — its connection to %<place>s and Ireland specifically: local status or
                        distribution, where near here it turns up, or the meaning of its Irish
                        name. This is the local hook — source it from BirdWatch Ireland (incl.
                        the relevant county branch) where you can.
        folklore      — a genuine piece of recorded lore, belief, or naming tradition, ideally
                        Irish (duchas.ie / celt.ucc.ie). Set "gated": true on folklore ALWAYS,
                        and frame it as lore, not fact.

      ABSOLUTE RULES:
      - "text_ga" must say EXACTLY what "text" says — a faithful translation, no fact added
        or dropped — in natural, idiomatic Irish with correct spelling and síntí fada. Use
        the bird's Irish name where "text" uses its English name. Keep folklore as folklore.
      - State ONLY what a fetched source supports. Every block needs at least one source you
        actually fetched with fetch_source; put the exact URL(s) in "sources".
      - Never invent, guess, or fill gaps from memory. If you cannot source something, omit
        that block. Two vivid, solid blocks beat three dull or shaky ones.
      - Never link the bird to weather, wind, temperature, or the sky.
      - Plain, calm sentences. No exclamation marks. Do not mention the station's own counts.
      - Output the JSON array only.
    PROMPT

    class << self
      # The last exception the model call raised (or nil) — so a caller can explain WHY
      # a run produced nothing (e.g. the Bedrock Anthropic use-case form isn't submitted)
      # rather than silently returning empty.
      attr_reader :last_error

      # Build (and store) bundles for the day's notable species that are DUE a refresh
      # under the importance-keyed backoff (Enrichment::Policy) — so a bird already
      # sourced recently isn't re-researched until its facts are worth revisiting.
      # `only:` forces one species regardless of backoff (manual/on-demand sourcing).
      # Returns the bundles produced (nil results filtered out).
      def run(date: Date.current, only: nil)
        return [build_one(date: date, **only.symbolize_keys)].compact if only

        facts = DailyFacts.for(date: date)
        due_species(facts, date).filter_map { |sp| build_one(date: date, **sp.symbolize_keys) }
      end

      # Today's species to source: every notable one that's due under the backoff — or,
      # when nothing notable is due, a small FLOOR of the day's most interesting species
      # that still lack facts & folklore. Without the floor an ordinary (or young) station,
      # where nothing clears the notable bar, would source nothing for ever; with it the
      # station builds a library a bird at a time (durable + backoff mean each is sourced
      # once, then left alone) and always has something to show.
      def due_species(facts, date)
        items = facts.fetch(:items, [])
        importance = items.to_h { |i| [i[:sci_name], i[:importance]] }
        due = ->(sci) { Policy.due?(sci, importance[sci].to_i, as_of: date) }

        notable = EnrichmentGate.species_for(facts).select { |sp| due.call(sp[:sci_name]) }
        return notable if notable.any?

        items.select { |i| due.call(i[:sci_name]) }.
          first(DAILY_FLOOR).map { |i| i.slice(:sci_name, :common_name, :irish_name) }
      end

      # One species → one stored bundle, or nil when nothing survived validation.
      def build_one(date:, sci_name:, common_name: nil, irish_name: nil)
        name = BirdName.lookup(sci_name)
        blocks = source_blocks(sci_name: sci_name, common_name: common_name || name.en)
        return nil if blocks.empty?

        bundle = EnrichmentBundle.find_or_initialize_by(sci_name: sci_name, date: date)
        bundle.update!(
          common_name: common_name || name.en,
          irish_name:  irish_name || name.ga,
          blocks:      blocks.map(&:to_h)
        )
        bundle
      end

      private

      def gate_species(date)
        EnrichmentGate.species_for(DailyFacts.for(date: date))
      end

      # Run the tool-use loop and return the surviving validated Blocks.
      def source_blocks(sci_name:, common_name:)
        @last_error = nil
        run_id = SecureRandom.uuid
        fetcher = SourceFetcher.new(sci_name: sci_name, run_id: run_id)
        final = converse_loop(sci_name: sci_name, common_name: common_name, fetcher: fetcher)
        fetched = SourceFetchLog.where(run_id: run_id).pluck(:url).to_set
        parse_blocks(final).filter_map { |raw| vet(raw, fetched) }
      rescue StandardError => e
        @last_error = e
        Rails.logger.warn("Enrichment::Builder: #{sci_name} failed (#{e.class}: #{e.message})")
        []
      end

      def converse_loop(sci_name:, common_name:, fetcher:)
        system = format(SYSTEM, place: station_place)
        messages = [{ role: 'user', content: [{ text: "Species: #{common_name} (#{sci_name})." }] }]

        MAX_ROUNDS.times do
          resp = Bedrock.converse_tools(system: system, messages: messages, tools: [FETCH_TOOL])
          message = resp.output.message
          messages << { role: 'assistant', content: echo(message.content) }

          uses = message.content.select(&:tool_use)
          return text_of(message.content) if resp.stop_reason != 'tool_use' || uses.empty?

          messages << { role: 'user', content: uses.map { |c| tool_result(c, fetcher) } }
        end

        # Still researching at the round cap — make it answer now from what it has.
        messages << { role: 'user', content: [{ text: FINALISE }] }
        resp = Bedrock.converse_tools(system: system, messages: messages, tools: [FETCH_TOOL])
        text_of(resp.output.message.content)
      end

      # Re-shape response content structs back into request-shape content hashes so the
      # assistant turn can be echoed into the next request.
      def echo(content)
        content.filter_map do |c|
          if c.tool_use
            { tool_use: { tool_use_id: c.tool_use.tool_use_id, name: c.tool_use.name, input: c.tool_use.input } }
          elsif c.text.present?
            { text: c.text }
          end
        end
      end

      def tool_result(content, fetcher)
        input = content.tool_use.input || {}
        url = input['url'] || input[:url]
        out = fetcher.fetch(url)
        text = out[:error] ? "ERROR: #{out[:error]}" : out[:text].to_s.first(MAX_FETCH_CHARS)
        { tool_result: { tool_use_id: content.tool_use.tool_use_id,
                         content:     [{ text: text }],
                         status:      out[:error] ? 'error' : 'success' } }
      end

      def text_of(content)
        content.filter_map(&:text).join.strip
      end

      # Pull the JSON array out of the model's final turn (tolerate a stray code fence).
      def parse_blocks(text)
        json = text.to_s[/\[.*\]/m]
        json ? Array(JSON.parse(json)) : []
      rescue JSON::ParserError
        []
      end

      # A block survives only if, once its citations are cut to URLs we truly fetched,
      # it still validates (folklore gated, non-station types sourced, etc.).
      def vet(raw, fetched)
        return nil unless raw.is_a?(Hash)

        cited = Array(raw['sources'] || raw[:sources]).select { |s| fetched.include?(s['url'] || s[:url]) }
        block = Block.from(raw.merge('sources' => cited))
        block if block&.valid?
      end

      # The station's precise place (config-resolved, never hard-coded), which anchors
      # the local-connection block. Falls back to the country when nothing is configured.
      def station_place
        Station.region.presence || 'a location in Ireland'
      end
    end
  end
end
