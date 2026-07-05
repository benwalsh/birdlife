# Narrates a DigestFacts object into a short personal note — the warm counterpart to
# the mechanical digest list. Same discipline as TodaySummary: Ruby has computed every
# fact; the model only phrases them, under absolute factual rules. Returns the note as
# paragraph lines, or nil on any failure/violation so the caller falls back to the
# deterministic email. A per-user one-shot at send time — no cache. Warmth degrades to
# correctness; it never blocks a send and never invents.
class DigestSummary
  SYSTEM = <<~PROMPT.freeze
    You write a short, warm daily note to one person about a rural bird-listening
    station%<where>s. It detects birds by sound and logs them. The reader has asked to
    hear about certain birds; foreground those.

    Write 2 to 4 short sentences (one small paragraph), based ONLY on the facts given.
    Lead with the birds the reader follows that were heard, then any flagged arrivals
    they subscribe to, then a light sense of the day. Warm but understated — a quiet
    note from the station, not a nature documentary.

    FACTUAL RULES — absolute:
    - State ONLY what is in the facts. Every clause traces to a given field.
    - Never invent or imply behaviour, migration, motivation, origin or destination.
    - Never link a bird to weather, wind, temperature or sky.
    - Counts and "first" claims are verbatim from the facts — never estimate or round.
    - Name a followed bird only if it is in the facts, with its given count.
    - If unsure something is supported, leave it out.

    STYLE: sentence case, no exclamation marks, no headings, no bullet points, no
    greeting or sign-off. Return ONLY the note text.
  PROMPT

  class << self
    # The note as an array of paragraph lines, or nil to fall back to the list email.
    def for(facts)
      return nil if Bedrock.disabled?

      raw = Bedrock.converse(system: format(SYSTEM, where: station_context), user: user_message(facts))
      note = clean(raw)
      valid?(note) ? note : nil
    rescue StandardError => e
      Rails.logger.warn("DigestSummary: generation failed (#{e.class}: #{e.message})")
      nil
    end

    # Public so a spec (or a human) can eyeball exactly what the model is asked.
    def user_message(facts)
      lines = ["Date: #{facts.date}."]
      lines << follows_line(facts.follows)
      lines << alerts_line(facts.alerts) if facts.alerts.any?
      lines << roundup_line(facts.roundup) if facts.roundup
      lines.join("\n")
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

    # Non-empty, not shouting, not a runaway generation.
    def valid?(note)
      note.any? && note.none? { |para| para.include?('!') } && note.join(' ').length.between?(20, 900)
    end

    def station_context
      Station.region.present? ? " in #{Station.region}" : ''
    end
  end
end
