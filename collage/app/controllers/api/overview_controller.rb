module Api
  # GET /api/overview?h= — everything the Birds tab renders.
  class OverviewController < BaseController
    def show
      tally = Detection.tally_within(current_window)
      render json: {
        window:     current_window,
        collage:    collage_json(CollagePresenter.new(tally)),
        numbers:    {
          species_today:       Detection.tally_for.size,
          detections_today:    Detection.today.count,
          detections_all_time: Detection.count
        },
        # Most common in the window (the tally is already loudest-first).
        top:        tally.first(6).map { |t| tally_json(t) },
        # Most recently heard, freshest first — Live's present-tense list (same sort the
        # kiosk's "recent" uses). The collage shows *which* birds; this shows *when*.
        recent:     tally.sort_by { |t| t.last_time.to_s }.last(8).reverse.map { |t| tally_json(t) },
        periods:    periods_json,
        first_seen: Detection.first_detections(8).map { |e| life_json(e) },
        almanac:    almanac_json,
        today:      today_json,
        notable:    notable_json,
        status:     AdminHealth.status
      }
    end
  end
end
