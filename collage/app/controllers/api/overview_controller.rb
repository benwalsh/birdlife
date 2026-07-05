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
        periods:    periods_json,
        first_seen: Detection.first_detections(4).map { |e| life_json(e) },
        almanac:    almanac_json,
        today:      today_json,
        breaking:   breaking_json
      }
    end
  end
end
