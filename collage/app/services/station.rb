# The listening station's own identity — its place — resolved from config or an API
# lookup, NEVER hard-coded. Éist is the product; a station is an *instance* defined
# entirely by configuration (culfinbirds is instance #1). So no view, prompt or
# component names a location literally: they all ask here, and get whatever this
# instance is configured/resolved to be (or nothing, gracefully).
class Station
  # The panel speaks ONE language, consistently — an admin picks which at /admin (stored
  # in Setting, so no redeploy). WHICH languages a station offers, and its default, are
  # config (station.yml: languages, default_language); the code names no language. A
  # single-language station simply never translates. culfinbirds is Irish-first ([ga, en]);
  # the shipped example is English-only.
  LANGUAGE_SETTING = 'station_language'.freeze
  # Display names for a language code; falls back to the code itself for anything unlisted.
  LANGUAGE_NAMES = { ga: 'Gaeilge', en: 'English', fr: 'Français', de: 'Deutsch',
                     es: 'Español', cy: 'Cymraeg', nl: 'Nederlands' }.freeze

  class << self
    # The languages this station offers, most-preferred first (from station.yml), or [:en].
    def languages
      Array(StationProfile.config['languages']).map { |l| l.to_s.to_sym }.presence || %i[en]
    end

    # The station's default/first-choice language — config, then the STATION_LANG env
    # override (legacy), then the first offered language.
    def default_language
      value = (StationProfile.config['default_language'].presence || ENV['STATION_LANG'].presence)&.to_sym
      value && languages.include?(value) ? value : languages.first
    end

    # True when the station shows more than one language — the only case the translation
    # pass and the second-language name are engaged at all.
    def multilingual?
      languages.size > 1
    end

    # The display name of a language code, for the admin picker.
    def language_name(code)
      LANGUAGE_NAMES.fetch(code.to_sym, code.to_s)
    end

    # The panel's current display language. Setting wins, then the config default; an
    # unknown stored value falls back safely to the default.
    def language
      value = Setting.get(LANGUAGE_SETTING, default_language).to_s.to_sym
      languages.include?(value) ? value : default_language
    end

    # Set by the admin surface. Rejects anything the station doesn't offer, so a bad post
    # can't wedge the wall into a language it can't render.
    def language=(value)
      value = value.to_s.to_sym
      raise ArgumentError, "unknown station language #{value.inspect}" unless languages.include?(value)

      Setting.set(LANGUAGE_SETTING, value)
    end

    # Where a guest goes to see more — this instance's public site, shown as calm
    # wayfinding on the panel. Config (station.yml url), then the STATION_URL env, else nil.
    # Never hard-coded to a particular site.
    def url
      StationProfile.config['url'].presence || ENV['STATION_URL'].presence
    end

    # A bilingual place label, or nil if nothing is configured or resolved. station.yml
    # place wins (a fixed station), then the BIRD_PLACE env, then the almanac's
    # reverse-geocode; the word is never in our code. The `:ga` key is the second-language
    # name (whatever the station's local language is), falling back to the English label.
    def place
      cfg = StationProfile.config['place'] || {}
      en = cfg['en'].presence || ENV['BIRD_PLACE'].presence || almanac_place[:en].presence
      return nil if en.blank?

      { en: en, ga: cfg['ga'].presence || ENV['BIRD_PLACE_GA'].presence || almanac_place[:ga].presence || en }
    end

    # A single-language place string for prose contexts (the LLM prompt), or nil.
    def region
      place&.fetch(:en, nil)
    end

    private

    def almanac_place
      value = (Almanac.current[:coords] || {})[:place]
      value.is_a?(Hash) ? value : { en: value, ga: value }
    end
  end
end
