module Enrichment
  # Irish sources handed to the Builder so an Irish bird's enrichment actually reaches Irish
  # material instead of defaulting to English Wikipedia. The general, reliable one is
  # Vicipéid (Irish-language Wikipedia): every common Irish bird has an article whose TITLE
  # is its Irish name, so the URL derives straight from the name — no per-species curation
  # needed, and it carries the Irish-name variants, meaning, and local status.
  #
  # Deliberately NOT seeded: BirdWatch Ireland (bot-protected — returns HTTP 307 to a
  # non-browser client, so the fetcher can never read it) and irishbirding.com (a sightings
  # site with no per-species pages). SEEDS is an extension point for hand-verified extra
  # pages (must be fetchable by SourceFetcher, i.e. return 200 to a plain client).
  module IrishSources
    VICIPEID = 'https://ga.wikipedia.org/wiki/'.freeze
    # sci_name => extra verified-fetchable Irish source URLs.
    SEEDS = {}.freeze

    module_function

    # The Irish source URLs to seed for a species — the Vicipéid article (derived from the
    # Irish name) plus any curated extras. Empty when there's no Irish name and no seed.
    def for(sci_name, irish_name)
      [vicipeid(irish_name), *SEEDS[sci_name]].compact
    end

    # The Vicipéid article URL for an Irish name ("Cág cosdearg" → …/wiki/Cág_cosdearg).
    # The fada stays readable in the citation; SourceFetcher percent-encodes it to fetch.
    def vicipeid(irish_name)
      return nil if irish_name.blank?

      VICIPEID + irish_name.strip.tr(' ', '_')
    end
  end
end
