require 'erb'

# The whole "TODAY" card, computed in Ruby so the view only iterates and prints
# (Ruby computes, the view renders). It assembles the daily voice (2-4 capped
# bullets), the past-24h sparkline as ready SVG paths, its time anchors, the
# right-aligned total, and the ambient footer readings. Everything bilingual, so
# the client picks a language without another round-trip.
class TodayCard
  # Irish day/month names for the header date (Ruby has no ga locale for these).
  GA_DAYS = %w[Domhnach Luan Máirt Céadaoin Déardaoin Aoine Satharn].freeze
  GA_MONTHS = [nil, 'Eanáir', 'Feabhra', 'Márta', 'Aibreán', 'Bealtaine', 'Meitheamh',
               'Iúil', 'Lúnasa', 'Meán Fómhair', 'Deireadh Fómhair', 'Samhain', 'Nollaig'].freeze
  # English weather word -> Tabler icon. Unmatched weather falls back to a cloud.
  WEATHER_ICONS = {
    'clear' => 'ti-sun', 'fair' => 'ti-sun', 'cloudy' => 'ti-cloud', 'overcast' => 'ti-cloud',
    'fog' => 'ti-fog', 'drizzle' => 'ti-cloud-drizzle', 'rain' => 'ti-cloud-rain',
    'showers' => 'ti-cloud-rain', 'snow' => 'ti-snowflake', 'thunderstorm' => 'ti-bolt'
  }.freeze
  # Null-delimited placeholder used while wrapping names — cannot occur in the text.
  MARK = "\u0000".freeze

  class << self
    def build(now: Time.current)
      facts = DailyFacts.for(now: now)
      summary = TodaySummary.current(facts: facts)
      counts, total = trailing_24h(now)
      spark = Sparkline.paths(counts)
      {
        date_label: date_label(now),
        summary:    emphasised_bullets(summary[:bullets], facts),
        source:     summary[:source],
        total:      total,
        sparkline:  { path: spark.path, fill: spark.fill, w: spark.w, h: spark.h },
        anchors:    anchors(now),
        footer:     footer_items(now)
      }
    end

    private

    def date_label(now)
      { en: now.strftime('%A, %-d %B'),
        ga: "#{GA_DAYS[now.wday]}, #{now.day} #{GA_MONTHS[now.month]}" }
    end

    # Bullets with species names marked up, HTML escaped, capped at four. English
    # common names go weight-500 (<strong>); Irish names take the serif voice-italic.
    # The view prints these as trusted, pre-shaped HTML.
    def emphasised_bullets(bullets, facts)
      marks = facts[:items].flat_map { |i| [[i[:common_name], :en], [i[:irish_name], :ga]] }.
              select { |name, _| name.present? }.uniq
      bullets.first(4).map { |bullet| emphasise(bullet, marks) }
    end

    # Longest names first, via a null-delimited placeholder so a name that is a
    # substring of another can't be double-wrapped.
    def emphasise(text, marks)
      safe = ERB::Util.html_escape(text)
      ordered = marks.sort_by { |name, _| -name.length }
      # Two passes, deliberately: stamp all placeholders first, then swap in tags —
      # so a short name can't match inside a longer name already turned into markup.
      # rubocop:disable Style/CombinableLoops
      ordered.each_with_index { |(name, _), i| safe = safe.gsub(ERB::Util.html_escape(name), "#{MARK}#{i}#{MARK}") }
      ordered.each_with_index { |(name, kind), i| safe = safe.gsub("#{MARK}#{i}#{MARK}", tag_for(name, kind)) }
      # rubocop:enable Style/CombinableLoops
      safe
    end

    def tag_for(name, kind)
      esc = ERB::Util.html_escape(name)
      kind == :ga ? %(<em class="voice">#{esc}</em>) : "<strong>#{esc}</strong>"
    end

    # Detections bucketed into the trailing 24 hours (oldest-first), plus the total.
    def trailing_24h(now)
      start = now - 24.hours
      buckets = Array.new(24, 0)
      rows = Detection.since(start).pluck(:Date, :Time)
      rows.each do |date, time|
        moment = combine(date, time)
        next unless moment

        idx = ((moment - start) / 3600).floor
        buckets[idx] += 1 if idx.between?(0, 23)
      end
      [buckets, rows.length]
    end

    def combine(date, time)
      return nil unless date && time

      Time.zone.local(date.year, date.month, date.day, time.hour, time.min, time.sec)
    rescue ArgumentError
      nil
    end

    # Four evenly-spaced clock-time ticks across the trailing 24h span — plain time
    # signals, no words (a true sparkline's minimal axis). Same label in both
    # languages (a clock time is a clock time).
    def anchors(now)
      start = now - 24.hours
      (0..3).map do |i|
        label = (start + (i * 8).hours).strftime('%H:%M')
        { x: (i / 3.0).round(4), en: label, ga: label }
      end
    end

    # The ambient readings - muted line-icon + short label pairs (never emoji).
    def footer_items(now)
      data = Almanac.current
      moon = MoonPhase.for(now.to_date)
      items = []
      items << weather_item(data[:weather]) if data[:weather]
      items << { icon: 'ti-moon', en: "#{moon.illumination}% #{moon.name.downcase}",
                 ga: "#{moon.illumination}% #{moon.name_ga.downcase}" }
      if (sun = data[:sun])
        items << { icon: 'ti-sunrise', en: sun[:rise], ga: sun[:rise] }
        items << { icon: 'ti-sunset', en: sun[:set], ga: sun[:set] }
      end
      items << { icon: 'ti-ripple', en: data[:tide][:label], ga: data[:tide][:label_ga] } if data[:tide]
      items << place_item(data)
      items
    end

    def weather_item(weather)
      { icon: WEATHER_ICONS.fetch(weather[:text], 'ti-cloud'),
        en: "#{weather[:temp]}°C #{weather[:text]}", ga: "#{weather[:temp]}°C #{weather[:text_ga]}" }
    end

    def place_item(data)
      coords = data[:coords] || {}
      place = coords[:place]
      place = { en: place, ga: place } if place.is_a?(String)
      place ||= {}
      en = place[:en] || ENV.fetch('BIRD_PLACE', 'Culfin')
      { icon: 'ti-map-pin', en: en, ga: place[:ga] || en }
    end
  end
end
