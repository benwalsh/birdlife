module Api
  # GET /api/journal?date=YYYY-MM-DD — a completed day's frozen diary entry: the final figures,
  # the warm narration and its citations, that day's new & notable, and the calendar bounds.
  # Defaults to yesterday (the last finished day); any date is clamped to what's available. The
  # entry itself is frozen once (JournalEntry) — figures and notable are recomputed from the
  # immutable detections on read. The stilled sparkline and the closing poem land in later phases.
  class JournalController < BaseController
    def show
      date = journal_date
      return render(json: unavailable) unless date

      entry = JournalEntry.for(date)
      facts = DailyFacts.for(date: date, now: date.end_of_day)
      render json: {
        date:       date.iso8601,
        date_label: TodayCard.date_label(date.in_time_zone),
        figures:    figures_json(facts),
        summary:    { en: TodayCard.emphasised_bullets(entry_bullets(entry, 'en'), facts, :en),
                      ga: TodayCard.emphasised_bullets(entry_bullets(entry, 'ga'), facts, :ga) },
        source:     entry&.source,
        sources:    entry_sources(entry),
        notable:    notable_json(as_of: date, days: 1),
        poem:       nil, # Phase 4b — a closing Irish poem for one of the day's birds
        available:  available_bounds
      }
    end

    private

    # The requested day, clamped to [first detection … yesterday]; nil when there is no
    # completed day yet (an empty or brand-new station).
    def journal_date
      first = first_detection_date
      return nil if first.nil? || first > Date.yesterday

      (parse_date(params[:date]) || Date.yesterday).clamp(first, Date.yesterday)
    end

    def figures_json(facts)
      loudest = Array(facts[:items]).max_by { |i| i[:call_count] }
      {
        species:    facts[:species_today],
        detections: facts[:detections_today],
        busiest:    loudest && { sci: loudest[:sci_name], en: loudest[:common_name],
                                 ga: loudest[:irish_name], count: loudest[:call_count] }
      }
    end

    def available_bounds
      { first: first_detection_date&.iso8601, last: Date.yesterday.iso8601 }
    end

    def first_detection_date
      @first_detection_date ||= Detection.minimum(:Date)&.to_date
    end

    def entry_bullets(entry, lang)
      Array(entry&.bullets&.with_indifferent_access&.dig(lang))
    end

    def entry_sources(entry)
      Array(entry&.sources).map { |s| s.with_indifferent_access.then { |h| { host: h[:host], url: h[:url] } } }
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end

    # A well-formed empty payload for a station with no completed day yet — the tab still
    # renders (an "ag éisteacht…" state) rather than erroring.
    def unavailable
      { date: nil, date_label: { en: '', ga: '' }, figures: { species: 0, detections: 0, busiest: nil },
        summary: { en: [], ga: [] }, source: nil, sources: [], notable: notable_json(days: 1),
        poem: nil, available: { first: nil, last: Date.yesterday.iso8601 } }
    end
  end
end
