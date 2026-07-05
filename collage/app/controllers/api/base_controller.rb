module Api
  # Shared JSON serialization for the SPA's data endpoints. All read-only GETs off
  # the existing model/presenter methods — the same numbers the server-rendered
  # views used, now shaped for React (and, later, api.culfinbirds.net).
  class BaseController < ApplicationController
    private

    # A SpeciesTally → the windowed-count shape (bilingual name + last heard).
    def tally_json(tally)
      {
        sci: tally.sci_name, en: tally.name.en, ga: tally.name.ga,
        count: tally.count, last_time: tally.last_time, confidence: tally.confidence
      }
    end

    # A LifeEntry → life-list shape (totals + conservation status).
    def life_json(entry)
      {
        sci: entry.sci_name, en: entry.name.en, ga: entry.name.ga, count: entry.count,
        first_seen: entry.first_seen, last_seen: entry.last_seen,
        conservation: Conservation.status(entry.sci_name),
        image: helpers.bird_illustration(entry.sci_name)
      }
    end

    def collage_json(collage)
      {
        width: collage.width, height: collage.height,
        species_count: collage.species_count, nodes: collage.nodes.map(&:to_h)
      }
    end

    def periods_json
      Detection.by_period.map { |label, count| { label: label, count: count } }
    end

    # The home page's "TODAY" card, shaped entirely in Ruby (bullets, sparkline
    # paths, anchors, footer) so the view only iterates and prints. See TodayCard.
    def today_json
      TodayCard.build(window_hours: current_window)
    end

    def moon_json
      moon = MoonPhase.for
      { name: moon.name, name_ga: moon.name_ga, illumination: moon.illumination, emoji: moon.emoji }
    end

    # Weather + tide + coordinates (from the cached almanac) + the moon, in one
    # blob for the facts row. Coords fall back to a config default; place is bilingual.
    def almanac_json
      data = Almanac.current
      coords = data[:coords] || {}
      place = coords[:place]
      place = { en: place, ga: place } if place.is_a?(String)
      place ||= {}
      lat = (coords[:lat] || ENV.fetch('BIRD_LAT', 53.55)).to_f
      lon = (coords[:lon] || ENV.fetch('BIRD_LON', -9.92)).to_f
      {
        weather: data[:weather], tide: data[:tide], sun: data[:sun], moon: moon_json,
        coords: { lat: lat, lon: lon, place_en: place[:en], place_ga: place[:ga] || place[:en],
                  label: helpers.format_coords(lat, lon) }
      }
    end
  end
end
