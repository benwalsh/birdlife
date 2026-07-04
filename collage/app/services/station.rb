# The listening station's own identity — its place — resolved from config or an API
# lookup, NEVER hard-coded. Éist is the product; a station is an *instance* defined
# entirely by configuration (culfinbirds is instance #1). So no view, prompt or
# component names a location literally: they all ask here, and get whatever this
# instance is configured/resolved to be (or nothing, gracefully).
class Station
  class << self
    # A bilingual place label, or nil if nothing is configured or resolved. Config
    # wins (a fixed cottage), then the almanac's reverse-geocode; the word is never
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
