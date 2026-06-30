require 'net/http'
require 'json'

# Cached Wikipedia species descriptions for the detail panel. English prose is
# keyed by scientific name (en.wikipedia resolves those); Irish prose by the
# bird's Irish name (ga.wikipedia uses Irish titles, not scientific ones, and
# only covers a fraction of species). Fetched once per species so the panel
# doesn't hit Wikipedia on every open.
class SpeciesInfo < ApplicationRecord
  validates :sci_name, presence: true, uniqueness: true

  class << self
    def english_for(sci, common = nil)
      info = find_or_initialize_by(sci_name: sci)
      return info.description if info.description.present?

      text = fetch(sci, 'en') || (common && fetch(common, 'en'))
      info.update(description: text, fetched_at: Time.current) if text
      text
    end

    # Irish article titles differ from the scientific name, so this fetches by
    # the bird's Irish name. fetched_ga_at records the attempt — including a miss
    # — so a species with no Irish article isn't re-fetched on every open.
    def irish_for(sci, ga_name)
      return nil if ga_name.blank?

      info = find_or_initialize_by(sci_name: sci)
      return info.description_ga if info.fetched_ga_at.present?

      text = fetch(ga_name, 'ga')
      info.update(description_ga: text, fetched_ga_at: Time.current)
      text
    end

    private

    def fetch(title, lang)
      uri = URI("https://#{lang}.wikipedia.org/api/rest_v1/page/summary/#{ERB::Util.url_encode(title.tr(' ', '_'))}")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'birdlife/1.0 (Connemara bird detector)')
      end
      return nil unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body)
      return nil if data['type'] == 'disambiguation'

      data['extract'].presence
    rescue StandardError
      nil
    end
  end
end
