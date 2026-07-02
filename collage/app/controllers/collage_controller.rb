class CollageController < ApplicationController
  STATION_SCREENS = %w[collage stats focus general].freeze
  STATION_DWELL_SECONDS = [ENV.fetch('STATION_DWELL_SECONDS', 300).to_i, 60].max

  def show
    @collage = collage
  end

  # The bare 800x480 SVG, no chrome — what the Inky shooter screenshots.
  def panel
    @collage = collage
    render partial: 'panel', layout: false
  end

  # A standalone page that mocks the physical panel: it fetches /panel and dithers
  # it to the Spectra-6 palette client-side (see the view). No @collage needed here.
  def emulator
    render layout: false
  end

  # The Éist Listening Station view — the 480x800 wall artefact, framed and run
  # through a CSS/SVG "e-ink" filter so a monitor gives a fair idea of what reads
  # on the physical 7.3" Inky (true resolution, muted + banded colour).
  def station
    tally = Detection.tally_within(current_window)
    @station_screen = station_screen
    @station_screens = STATION_SCREENS
    @station_dwell_seconds = STATION_DWELL_SECONDS
    @collage = CollagePresenter.new(tally, width: 412, height: 600, top_inset: 10, bottom_inset: 10)
    @species_today = Detection.tally_for.size
    @detections_today = Detection.today.count
    @species_all_time = Detection.life_list.size
    @detections_all_time = Detection.count
    @recent = tally.sort_by { |t| t.last_time.to_s }.last(6).reverse
    @featured = station_feature(tally)
    @periods = Detection.by_period
    @moon = MoonPhase.for
    render layout: false
  end

  def station_next
    next_screen = station_screen(offset: 1)

    render json: {
      screen: next_screen,
      dwell_seconds: STATION_DWELL_SECONDS,
      url: station_path(screen: next_screen)
    }
  end

  private

  def collage
    CollagePresenter.new(Detection.tally_within(current_window))
  end

  def station_screen(offset: 0)
    requested = params[:screen].to_s
    return requested if STATION_SCREENS.include?(requested) && offset.zero?

    slot = (Time.current.to_i / STATION_DWELL_SECONDS) + offset
    STATION_SCREENS[slot % STATION_SCREENS.size]
  end

  def station_feature(tally)
    return nil if tally.empty?

    tally.max_by { |item| [station_time(item.last_time)&.to_i || 0, item.count] }
  end

  def station_time(value)
    return nil unless value

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
  helper_method :station_time
end
