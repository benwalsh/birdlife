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

  # /station — the single Inky screen: the collage in the house style, framed and
  # run through a CSS/SVG "e-ink" filter so a monitor gives a fair idea of what
  # reads on the physical 7.3" Spectra-6 panel. A title, the collage big and
  # dominant, and a footer (time · moon · species). Nothing that cycles — e-ink
  # refreshes on change, it doesn't rotate.
  def station
    tally = Detection.tally_within(current_window)
    # Portrait cluster (taller than wide) so the flock fills the tall Inky panel
    # with big birds, rather than a landscape band floating in whitespace.
    @collage = CollagePresenter.new(tally, width: 452, height: 600, top_inset: 4, bottom_inset: 4,
                                           margin: 6, x_bias: 0.82, y_bias: 1.0)
    @species_today = Detection.tally_for.size
    @moon = MoonPhase.for
    @news = station_news(tally)
    render layout: false
  end

  private

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

  # One calm line of "news" for the glass, from the same facts engine the website
  # reads — no LLM on the panel (the wall owes the internet nothing). Leads with the
  # day's most notable item (a first / arrival / rarity); falls back to the busiest
  # species when nothing stands out.
  def station_news(tally)
    return nil if tally.empty?

    notable = DailyFacts.for[:notable_today].first
    if notable
      name = BirdName.lookup(notable[:sci_name])
      "#{name.ga || name.en} · #{station_news_note(notable)}"
    else
      top = tally.max_by(&:count)
      name = top.name
      "#{name.ga || name.en} leads the morning · #{top.count} calls"
    end
  end

  # The house-voice reason a notable item matters, from its flags.
  def station_news_note(item)
    return 'first record at the station' if item[:flags].include?('all_time_first')
    return 'first of the year' if item[:flags].include?('year_first')

    'a scarce visitor'
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
