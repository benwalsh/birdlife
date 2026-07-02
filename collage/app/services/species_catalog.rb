# The full field-guide library: every species we ship an illustration for — the
# universe the atlas can browse, beyond just what's been heard. Source of truth
# is the illustration set (one perched PNG per species), matched back to BirdNET
# scientific names through the shared label file.
class SpeciesCatalog
  ILLUSTRATIONS_DIR = Rails.root.join('../avian/assets/illustrations')

  class << self
    # Every scientific name we have art for, ordered by display (Irish) name.
    def all_sci
      @all_sci ||= BirdName::ENGLISH.keys.
                   select { |sci| slugs.include?(sci.downcase.tr(' ', '-')) }.
                   sort_by { |sci| name_key(sci) }
    end

    private

    # Perched illustration slugs on disk (the flight "-2" variants don't count
    # as separate species).
    def slugs
      @slugs ||= Dir.glob(ILLUSTRATIONS_DIR.join('*.png')).
                 map { |path| File.basename(path, '.png') }.
                 reject { |slug| slug.end_with?('-2') }.
                 to_set
    end

    def name_key(sci)
      name = BirdName.lookup(sci)
      (name.ga || name.en).downcase
    end
  end
end
