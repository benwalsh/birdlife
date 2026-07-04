require 'net/http'
require 'json'

# The station's surroundings — weather, tide, and coordinates — fetched on a
# schedule and cached to disk. Two hard rules, both from the offline-first keel:
#
#   * `current` NEVER touches the network. Page loads read the last-known cache
#     (which may be hours old on flaky rural broadband — that's fine, it's a wall
#     display, not a forecast service). It is always fast and works offline.
#   * `refresh` (run by the birdlife-almanac timer every 30 min) is best-effort:
#     a failure in one source keeps the others and the previous value; a total
#     outage just leaves the last good cache in place.
#
# Everything uses Open-Meteo, which needs no API key — the right trade for a box
# nobody tends. The moon is NOT here: it's a pure calculation (see MoonPhase), so
# it never goes stale and needs no fetch.
class Almanac
  STORE = Rails.root.join('storage/almanac.json')
  HTTP_TIMEOUT = 4

  # Open-Meteo `weather_code` (WMO) → [English, Irish, emoji] for the facts row.
  # Terms follow Met Éireann's forecast vocabulary (grianmhar, scamallach,
  # ceathanna, báisteach, ceobhrán, modartha, sneachta, stoirm thoirní …) rather
  # than a literal translation.
  WMO = {
    0  => ['clear', 'spéir ghlan', '☀️'],
    1  => ['fair', 'breá', '🌤️'],
    2  => ['partly cloudy', 'scamallach go páirteach', '⛅'],
    3  => ['overcast', 'modartha', '☁️'],
    45 => ['fog', 'ceo', '🌫️'],
    48 => ['freezing fog', 'ceo sioctha', '🌫️'],
    51 => ['light drizzle', 'ceobhrán éadrom', '🌦️'],
    53 => ['drizzle', 'ceobhrán', '🌦️'],
    55 => ['heavy drizzle', 'ceobhrán trom', '🌦️'],
    56 => ['freezing drizzle', 'ceobhrán sioctha', '🌧️'],
    57 => ['freezing drizzle', 'ceobhrán sioctha', '🌧️'],
    61 => ['light rain', 'báisteach éadrom', '🌦️'],
    63 => ['rain', 'báisteach', '🌧️'],
    65 => ['heavy rain', 'báisteach throm', '🌧️'],
    66 => ['freezing rain', 'báisteach shioctha', '🌧️'],
    67 => ['freezing rain', 'báisteach shioctha', '🌧️'],
    71 => ['light snow', 'sneachta éadrom', '🌨️'],
    73 => ['snow', 'sneachta', '🌨️'],
    75 => ['heavy snow', 'sneachta trom', '❄️'],
    77 => ['snow grains', 'gráinní sneachta', '🌨️'],
    80 => ['showers', 'ceathanna', '🌦️'],
    81 => ['showers', 'ceathanna', '🌦️'],
    82 => ['heavy showers', 'ceathanna troma', '🌧️'],
    85 => ['snow showers', 'ceathanna sneachta', '🌨️'],
    86 => ['snow showers', 'ceathanna sneachta', '🌨️'],
    95 => ['thunderstorm', 'stoirm thoirní', '⛈️'],
    96 => ['thunderstorm', 'stoirm thoirní', '⛈️'],
    99 => ['thunderstorm', 'stoirm thoirní', '⛈️']
  }.freeze
  # Tide turning point → [English, Irish] (Lán mara = high water, Lag trá = ebb).
  TIDE_LABELS = { high: ['High tide', 'Lán mara'], low: ['Low tide', 'Lag trá'] }.freeze
  DEFAULT_COORDS = { lat: 53.55, lon: -9.92, place: 'Culfin' }.freeze
  # OSM address keys, most-local first — the "best guess" for where we are.
  PLACE_KEYS = %w[hamlet village locality town suburb city municipality].freeze

  class << self
    def current
      return blank unless STORE.exist?

      data = JSON.parse(STORE.read, symbolize_names: true)
      data[:fetched_at] = safe_time(data[:fetched_at])
      data
    rescue JSON::ParserError, SystemCallError
      blank
    end

    def refresh(now: Time.current)
      coords = resolve_coords
      prev = current
      forecast = fetch_forecast(coords)
      data = {
        coords:     coords,
        weather:    forecast[:weather] || prev[:weather],
        sun:        forecast[:sun] || prev[:sun],
        tide:       fetch_tide(coords, now) || prev[:tide],
        fetched_at: now.iso8601
      }
      write(data)
      data
    end

    # --- Pure helpers (no network; unit-tested) --------------------------------

    # A WMO code + temperature into the facts-row shape. Unknown codes degrade to
    # a thermometer rather than blowing up.
    def weather_from(temp, code)
      en, ga, emoji = WMO.fetch(code.to_i, ['—', '—', '🌡️'])
      { temp: temp.round, text: en, text_ga: ga, emoji: emoji }
    end

    # Today's sunrise/sunset (HH:MM) from Open-Meteo's daily arrays, or nil.
    def sun_from(daily)
      rise = daily && daily['sunrise']&.first
      set = daily && daily['sunset']&.first
      return nil unless rise && set

      { rise: hhmm_of(rise), set: hhmm_of(set) }
    end

    # "2026-07-03T05:12" → "05:12".
    def hhmm_of(iso)
      iso.to_s[/T(\d{2}:\d{2})/, 1]
    end

    # The next tide turning point after `now`, read off the hourly sea-level
    # series as the first future local max (high) or min (low).
    def next_tide(times, heights, now)
      points = times.zip(heights).filter_map { |t, v| [safe_time(t), v.to_f] if t && v }
      (1...(points.size - 1)).each do |i|
        time, height = points[i]
        next if time.nil? || time <= now

        prev_h = points[i - 1][1]
        next_h = points[i + 1][1]
        return tide(:high, time) if height >= prev_h && height >= next_h
        return tide(:low, time)  if height <= prev_h && height <= next_h
      end
      nil
    end

    # Best-guess place label from an OSM reverse-geocode address hash — the most
    # local named thing, then the county (e.g. "Tullycross, County Galway").
    def place_from(address)
      return nil unless address

      local = PLACE_KEYS.filter_map { |k| address[k] }.first
      [local, address['county']].compact.uniq.join(', ').presence
    end

    private

    def blank = { coords: nil, weather: nil, sun: nil, tide: nil, fetched_at: nil }

    def tide(kind, time)
      hhmm = time.strftime('%H:%M')
      en, ga = TIDE_LABELS.fetch(kind)
      { type: kind.to_s, time: hhmm, label: "#{en} #{hhmm}", label_ga: "#{ga} #{hhmm}" }
    end

    # Where are we? Configured coordinates win (the cottage is a fixed spot);
    # otherwise the device auto-detects via IP geolocation, then the last cache,
    # then Culfin. The place name is a best guess: an explicit BIRD_PLACE if set,
    # else a reverse-geocode of the coordinates, else whatever IP geo named.
    def resolve_coords
      base = configured_latlon || fetch_geo || current[:coords] || DEFAULT_COORDS
      { lat: base[:lat], lon: base[:lon], place: resolve_place(base) }
    end

    # A bilingual place label {en:, ga:}. An explicit BIRD_PLACE wins (same in
    # both); otherwise reverse-geocode once per language, so a Gaeltacht townland
    # reads in Irish (Conamara) or English (Connemara) as the chrome toggle asks.
    def resolve_place(base)
      return { en: ENV['BIRD_PLACE'], ga: ENV['BIRD_PLACE'] } if ENV['BIRD_PLACE'].present?

      en = reverse_place(base[:lat], base[:lon], 'en')
      ga = reverse_place(base[:lat], base[:lon], 'ga')
      fallback = en || ga || base_place(base)
      { en: en || fallback, ga: ga || fallback }
    end

    def base_place(base)
      place = base[:place]
      place.is_a?(Hash) ? (place[:en] || place[:ga]) : place
    end

    def configured_latlon
      return nil unless ENV['BIRD_LAT'].present? && ENV['BIRD_LON'].present?

      { lat: ENV['BIRD_LAT'].to_f, lon: ENV['BIRD_LON'].to_f }
    end

    def fetch_geo
      json = get_json('http://ip-api.com/json/?fields=status,lat,lon,city')
      return nil unless json && json['status'] == 'success'

      { lat: json['lat'].to_f, lon: json['lon'].to_f, place: json['city'] }
    end

    # Reverse-geocode to a locality via OSM Nominatim in one language (no key; a
    # valid User-Agent + our 30-min cadence stay well within its usage policy).
    def reverse_place(lat, lon, lang)
      json = get_json("https://nominatim.openstreetmap.org/reverse?lat=#{lat}&lon=#{lon}&format=jsonv2&zoom=13&addressdetails=1&accept-language=#{lang}")
      place_from(json && json['address'])
    end

    # One Open-Meteo call for both the current conditions and today's sun times.
    def fetch_forecast(coords)
      json = get_json("https://api.open-meteo.com/v1/forecast?latitude=#{coords[:lat]}&longitude=#{coords[:lon]}&current=temperature_2m,weather_code&daily=sunrise,sunset&timezone=auto")
      return {} unless json

      cur = json['current']
      if cur && cur['temperature_2m'] && cur['weather_code']
        weather = weather_from(cur['temperature_2m'],
                               cur['weather_code'])
      end
      { weather: weather, sun: sun_from(json['daily']) }.compact
    end

    def fetch_tide(coords, now)
      json = get_json("https://marine-api.open-meteo.com/v1/marine?latitude=#{coords[:lat]}&longitude=#{coords[:lon]}&hourly=sea_level_height_msl&timezone=auto&forecast_days=2")
      hourly = json && json['hourly']
      return nil unless hourly && hourly['time'] && hourly['sea_level_height_msl']

      next_tide(hourly['time'], hourly['sea_level_height_msl'], now)
    end

    def get_json(url)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                            open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'Eist/1.0 (+https://culfinbirds.net)')
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    rescue StandardError
      nil
    end

    def safe_time(value)
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def write(data)
      tmp = STORE.sub_ext('.tmp')
      tmp.write(JSON.pretty_generate(data))
      tmp.rename(STORE.to_s) # atomic replace so a reader never sees a half-written file
    end
  end
end
