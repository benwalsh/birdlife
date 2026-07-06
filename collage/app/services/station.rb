# The listening station's own identity — its place — resolved from config or an API
# lookup, NEVER hard-coded. Éist is the product; a station is an *instance* defined
# entirely by configuration (culfinbirds is instance #1). So no view, prompt or
# component names a location literally: they all ask here, and get whatever this
# instance is configured/resolved to be (or nothing, gracefully).
class Station
  # The panel speaks ONE language, consistently — an admin picks which at /admin (stored
  # in Setting, so no redeploy). Irish-first is the default: the bilingual Irish name is
  # the centrepiece and this is a Connemara wall. The website keeps its own live toggle;
  # this is only the fixed panel's voice.
  LANGUAGES = %i[ga en].freeze
  LANGUAGE_NAMES = { ga: 'Gaeilge', en: 'English' }.freeze
  LANGUAGE_SETTING = 'station_language'.freeze

  class << self
    # The panel's current display language (:ga or :en). Setting wins, then a config
    # default, then Irish; an unknown stored value falls back safely.
    def language
      value = Setting.get(LANGUAGE_SETTING, ENV.fetch('STATION_LANG', 'ga')).to_s.to_sym
      LANGUAGES.include?(value) ? value : :ga
    end

    # Set by the admin surface. Rejects anything off the list, so a bad post can't wedge
    # the wall into a language it can't render.
    def language=(value)
      value = value.to_s.to_sym
      raise ArgumentError, "unknown station language #{value.inspect}" unless LANGUAGES.include?(value)

      Setting.set(LANGUAGE_SETTING, value)
    end

    # Where a guest goes to see more — this instance's public site, shown as calm
    # wayfinding on the panel. Config, never hard-coded (culfinbirds.net is instance #1).
    def url
      ENV.fetch('STATION_URL', 'culfinbirds.net')
    end

    # A bilingual place label, or nil if nothing is configured or resolved. Config
    # wins (a fixed station), then the almanac's reverse-geocode; the word is never
    # in our code.
    def place
      en = ENV['BIRD_PLACE'].presence || almanac_place[:en].presence
      return nil if en.blank?

      { en: en, ga: ENV['BIRD_PLACE_GA'].presence || almanac_place[:ga].presence || en }
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
