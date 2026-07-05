module Enrichment
  # Stage 2 of the pipeline: per-user ASSEMBLY. Given one reader's day (DigestFacts —
  # the birds they follow, the arrivals they take, the station's overall day) and the
  # day's shared EnrichmentBundles (Stage 1's cited blocks), Nova Lite assembles the
  # personal note: it chooses which blocks to use, orders them behind the reader's own
  # birds, and writes light glue prose. It is glue-only — it may drop, reorder and
  # frame blocks, but never edit the inside of one and never introduce a fact of its
  # own. Not a channel: this returns the note text; a Notifier renders it to email (or,
  # later, to another channel).
  #
  # Returns the note as paragraph lines, or nil on any failure/violation so the caller
  # falls back to the plain DigestSummary and then the mechanical list. Warmth degrades
  # to correctness; enrichment is a bonus that never blocks or corrupts a send.
  class Assembler
    SYSTEM = <<~PROMPT.freeze
      You assemble ONE short daily note for a single reader of a rural Irish bird-listening
      station%<where>s, by STITCHING pre-written pieces together. You are not the writer —
      the interesting writing is already done.

      You are given (a) the reader's day as FACTS and (b) a CATALOGUE of pre-written,
      pre-sourced blocks about individual birds. Your job: pick the best blocks for THIS
      reader, order them behind their own birds, and join them with the least glue that reads
      well.

      Shape: 2 to 4 short sentences (one small paragraph). Lead with the birds the reader
      FOLLOWS that were heard today, by name and with their given counts. Then carry ONE or
      TWO blocks from the CATALOGUE — preferring blocks about the birds the reader follows,
      and a MIX (a striking fact plus a bit of local colour or folklore) over two of a kind.
      Use the blocks' own words wherever you can. If no block fits the reader's birds, give
      the counts and stop.

      RULES:
      - Use ONLY the FACTS and the CATALOGUE. Add nothing of your own — no fact, number,
        behaviour, or scene-setting. Your own words are connective glue only; everything with
        content comes from a block.
      - Keep each block's meaning exactly; you may shorten and reword for flow, never embellish
        or merge blocks into a claim neither one made.
      - A block marked "lore" is folklore — carry it as an old belief or name, never as fact.
      - Counts and "first" claims are verbatim from the FACTS. A count is how many TIMES a bird
        was heard, not how many birds: "heard 137 times", never "137 house sparrows".
      - At most two catalogue blocks.

      STYLE: sentence case, no exclamation marks, no headings, no bullet points, no greeting
      or sign-off. Return ONLY the note text.
    PROMPT

    class << self
      # The assembled note as paragraph lines, or nil to fall back.
      def for(user:, date: Date.yesterday)
        return nil if Bedrock.disabled?

        facts = DigestFacts.for(user: user, date: date)
        catalogue = catalogue_for(facts, date)
        return nil if catalogue.empty? # nothing to add over the plain summary

        raw = Bedrock.converse(system: format(SYSTEM, where: station_context),
                               user: user_message(facts, catalogue), max_tokens: 600)
        note = clean(raw)
        valid?(note) ? note : nil
      rescue StandardError => e
        Rails.logger.warn("Enrichment::Assembler: assembly failed (#{e.class}: #{e.message})")
        nil
      end

      # The exact prompt body — public so a spec or a human can eyeball it.
      def user_message(facts, catalogue)
        lines = ['FACTS', "Date: #{facts.date}.", follows_line(facts.follows)]
        lines << alerts_line(facts.alerts) if facts.alerts.any?
        lines << roundup_line(facts.roundup) if facts.roundup
        lines << ''
        lines << 'CATALOGUE'
        lines.concat(catalogue)
        lines.join("\n")
      end

      # The blocks available to this reader, the birds they follow first. A flat list
      # of "[Bird — context] (type) text" lines Nova can pick from.
      def catalogue_for(facts, date)
        followed = facts.follows.index_by { |f| f[:sci] }
        bundles = EnrichmentBundle.for_date(date).select { |b| b.block_objects.any? }
        ordered = bundles.sort_by { |b| followed.key?(b.sci_name) ? 0 : 1 }

        ordered.flat_map do |bundle|
          who = bundle.common_name || BirdName.lookup(bundle.sci_name).en
          follow = followed[bundle.sci_name]
          tag = follow ? " (a bird the reader follows, heard #{follow[:count]}×)" : ''
          bundle.block_objects.map do |block|
            kind = block.gated? ? "#{block.type}, lore" : block.type
            "- [#{who}#{tag}] (#{kind}) #{block.text}"
          end
        end
      end

      private

      def follows_line(follows)
        return 'Birds the reader follows heard today: none.' if follows.empty?

        list = follows.map { |f| "#{f[:en]} (#{f[:ga]}) x#{f[:count]}" }.join('; ')
        "Birds the reader follows heard today: #{list}."
      end

      def alerts_line(alerts)
        list = alerts.map { |a| "#{a[:kind].tr('_', ' ')}: #{a[:en]}" }.join('; ')
        "Flagged arrivals they subscribe to: #{list}."
      end

      def roundup_line(roundup)
        note = roundup[:activity_note] ? ", #{roundup[:activity_note].tr('_', ' ')}" : ''
        "The station day overall: #{roundup[:species_today]} species, #{roundup[:detections_today]} detections#{note}."
      end

      def clean(raw)
        raw.to_s.strip.split(/\n{2,}/).map { |para| para.tr("\n", ' ').squeeze(' ').strip }.reject(&:empty?)
      end

      def valid?(note)
        note.any? && note.none? { |para| para.include?('!') } && note.join(' ').length.between?(20, 900)
      end

      def station_context
        Station.region.present? ? " in #{Station.region}" : ''
      end
    end
  end
end
