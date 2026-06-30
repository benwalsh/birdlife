require 'json'

# Bilingual name lookup, keyed by BirdNET scientific name.
#
# Reads the standard BirdNET locale files we maintain at the repo root
# (model/l18n/labels_{en,ga}.json) — the single source of truth shared with the
# Python side. A locale file carries every BirdNET key; a species with no Irish
# name falls back to the English string, which we treat as "no Irish" so the
# collage shows English only rather than repeating it.
class BirdName
  Name = Data.define(:sci, :en, :ga)

  L18N_DIR = Rails.root.join('../model/l18n')
  # Read as UTF-8 explicitly: the Irish names carry accented characters (á, é, í,
  # ó, ú), and a headless Pi's default locale can be non-UTF-8, which would
  # otherwise mangle them. (LANG/LC_ALL=C.UTF-8 is also set in the systemd units.)
  ENGLISH  = JSON.parse(File.read(L18N_DIR.join('labels_en.json'), encoding: 'UTF-8')).freeze
  IRISH    = JSON.parse(File.read(L18N_DIR.join('labels_ga.json'), encoding: 'UTF-8')).freeze

  class << self
    def lookup(sci)
      en = ENGLISH.fetch(sci, sci)
      ga_raw = IRISH[sci]
      ga = ga_raw if ga_raw && ga_raw != en
      Name.new(sci:, en:, ga:)
    end
  end
end
