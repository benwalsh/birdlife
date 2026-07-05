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
    MAX_ROUNDS = 8
    MAX_FETCH_CHARS = 6000
    # When research runs long, this forces the model to stop and answer from what it has
    # already fetched, so a thorough explorer still yields blocks instead of nothing.
    FINALISE = 'Stop searching now. Using ONLY the sources you have already fetched ' \
               'successfully, output the JSON array of blocks and nothing else.'.freeze

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

      Wikipedia (en.wikipedia.org) is the most reliably fetchable source and its species,
      folklore and mythology pages are deep — lead with it, and follow its links. CELT
      (celt.ucc.ie) is good for older Irish texts. BirdWatch Ireland and dúchas.ie are
      worth trying but you often WON'T know a working URL — if a fetch fails, do NOT keep
      guessing paths on the same site; move on and use what you have. A few good sources
      beat a long hunt. Fetch what you need, then return the blocks.

      Return up to 3 blocks as a JSON array and NOTHING else — no prose, no code fence.
      Each block is an object:
        { "type": "fact" | "regional_note" | "folklore",
          "id": "short-kebab-id",
          "text": "one or two plain sentences",
          "sources": [ { "host": "en.wikipedia.org", "url": "https://..." } ],
          "gated": false }

      Aim for ONE of each type when the sources support it:
        fact          — the most vivid, memorable thing about the species: a striking
                        behaviour, its voice, how it feeds or nests, a naming quirk. Reach for
                        what would make a listener look up, NOT its length and weight. Skip
                        bare measurements.
        regional_note — its connection to %<place>s and Ireland specifically: local status or
                        distribution, where near here it turns up, or the meaning of its Irish
                        name. This is the local hook — source it from BirdWatch Ireland (incl.
                        the relevant county branch) where you can.
        folklore      — a genuine piece of recorded lore, belief, or naming tradition, ideally
                        Irish (duchas.ie / celt.ucc.ie). Set "gated": true on folklore ALWAYS,
                        and frame it as lore, not fact.

      ABSOLUTE RULES:
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
        importance = facts.fetch(:items, []).to_h { |i| [i[:sci_name], i[:importance]] }
        EnrichmentGate.species_for(facts).filter_map do |sp|
          next unless Policy.due?(sp[:sci_name], importance[sp[:sci_name]].to_i, as_of: date)

          build_one(date: date, **sp.symbolize_keys)
        end
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
