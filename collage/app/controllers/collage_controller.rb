class CollageController < ApplicationController
  # The four cards /kiosk cycles through. /station shows only the first (collage).
  KIOSK_SCREENS = %w[collage stats focus general].freeze
  # How long each kiosk card holds before the next fades in (seconds). Floor of 8s
  # so an over-eager env value can't strobe the display.
  KIOSK_DWELL_SECONDS = [ENV.fetch('KIOSK_DWELL_SECONDS', 30).to_i, 8].max

  # / — the Éist React SPA host. The editorial layout renders only the mount
  # point; all view data comes from /api/*. The first paint is seeded by a small
  # bootstrap blob so the chrome (auth, language) needs no round-trip.
  layout 'editorial', only: :show

  def show
    @bootstrap = {
      current_user: user_payload,
      ui_lang:      ui_lang,
      windows:      WINDOWS,
      place:        Station.place,
      favourites:   followed_sci_names,
      assets:       { cruach: helpers.asset_path('cruach.png') }
    }
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

  # /kiosk — no chrome, no nav: the four cards, cycling client-side (a smooth
  # cross-fade, no reload flash), for a passive monitor/iPad in portrait or
  # landscape. Full colour — a real screen, not the e-ink panel.
  def kiosk
    load_cards
    @dwell_seconds = KIOSK_DWELL_SECONDS
    render layout: false
  end

  # /station — the clean 480×800 screen the Inky shows and the shooter captures: a
  # title, the collage big and dominant, a news line, a footer (time · moon · species).
  # No frame, no e-ink filter — the panel dithers a full-colour source itself. Nothing
  # cycles: e-ink refreshes on change, it doesn't rotate.
  def station
    load_station
    render layout: false
  end

  # /station/preview — the same screen wrapped in the bog-oak frame + a CSS/SVG e-ink
  # emulation, so a desktop browser previews what reads on the physical panel.
  def station_preview
    load_station
    render layout: false
  end

  private

  def load_station
    tally = Detection.tally_within(current_window)
    # Portrait cluster (taller than wide) so the flock fills the tall Inky panel
    # with big birds, rather than a landscape band floating in whitespace.
    @collage = CollagePresenter.new(tally, width: 452, height: 600, top_inset: 4, bottom_inset: 4,
                                           margin: 6, x_bias: 0.82, y_bias: 1.0)
    @species_today = Detection.tally_for.size
    @moon = MoonPhase.for
    @news = station_news
  end

  def collage
    CollagePresenter.new(Detection.tally_within(current_window))
  end

  # Everything the four kiosk cards need in one pass.
  def load_cards
    tally = Detection.tally_within(current_window)
    @screens = KIOSK_SCREENS
    @collage = CollagePresenter.new(tally, width: 900, height: 620)
    @species_today = Detection.tally_for.size
    @detections_today = Detection.today.count
    @species_all_time = Detection.life_list.size
    @detections_all_time = Detection.count
    @recent = tally.sort_by { |t| t.last_time.to_s }.last(6).reverse
    @featured = station_feature(tally)
    @periods = Detection.by_period
    @moon = MoonPhase.for
  end

  # One calm line of news for the glass — a subset of the exact same content the website
  # and the email carry, never anything of the panel's own. It's the freshest breaking
  # Event (rarity / first-ever / seasonal), shown with the shared bilingual kind label,
  # Irish-first in the wall's voice. Quiet days carry no news, so the view falls through
  # to the listening state rather than the panel inventing a headline. No LLM on the
  # panel — it reads a fired Event from the store, it doesn't narrate.
  def station_news
    event = Event.breaking.first
    return nil unless event

    label = event.kind_label
    name = BirdName.lookup(event.sci_name)
    "#{label[:ga] || label[:en]} · #{name.ga || name.en}"
  end

  # The card's featured bird: most recently heard, ties broken by call count.
  def station_feature(tally)
    return nil if tally.empty?

    tally.max_by { |item| [station_time(item.last_time).to_i, item.count] }
  end

  def station_time(value)
    return nil unless value

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
  helper_method :station_time
end
