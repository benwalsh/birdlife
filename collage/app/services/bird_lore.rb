# Curated literary/folkloric lore per species (config/bird_lore.yml) — attributed, public-domain
# verse and tales quoted verbatim to round off a Journal entry. The model never writes these;
# the reference supplies the exact, credited text (same discipline as Feilire). Returns a
# string-keyed { 'kind' =>, 'text' =>, 'attribution' => } hash, or nil.
class BirdLore
  class << self
    def for(sci_name)
      entries[sci_name.to_s]
    end

    private

    def entries
      @entries ||= load_entries
    end

    def load_entries
      path = Rails.root.join('config/bird_lore.yml')
      path.exist? ? (YAML.safe_load_file(path) || {}) : {}
    rescue Psych::SyntaxError => e
      Rails.logger.warn("BirdLore: bad bird_lore.yml (#{e.message})")
      {}
    end
  end
end
