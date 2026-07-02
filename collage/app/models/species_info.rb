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

    # A playable call/song sample (a Wikimedia Commons audio URL) for the inline
    # player. fetched_song_at records the attempt — including a miss (some species
    # have no recording) — so we don't re-hit Wikipedia on every modal open.
    def song_for(sci)
      info = find_or_initialize_by(sci_name: sci)
      return info.song_url if info.fetched_song_at.present?

      url = fetch_song(sci)
      info.update(song_url: url, fetched_song_at: Time.current)
      url
    end

    private

    # Two sources, most-trustworthy first: audio embedded in the species'
    # Wikipedia article, else a Commons search. nil if neither has a recording.
    def fetch_song(sci)
      article_song(sci) || commons_song(sci)
    rescue StandardError
      nil
    end

    # Audio embedded in the species' English Wikipedia article (by scientific
    # name — it redirects to the common-name page). Reliable: it's curated onto
    # that exact article.
    def article_song(sci)
      media = get_json("https://en.wikipedia.org/api/rest_v1/page/media-list/#{ERB::Util.url_encode(sci.tr(' ', '_'))}")
      audio = media && Array(media['items']).find { |item| item['type'] == 'audio' }
      audio && audio['title'].present? ? file_url(audio['title']) : nil
    end

    # Fallback: search Wikimedia Commons for an audio file — but accept only one
    # whose filename contains the scientific name. That filter is essential: a
    # bare search for a species Commons has no recording of returns junk (a
    # same-named food dish, an unrelated speech); requiring the binomial in the
    # title rejects those while keeping genuine "Genus_species_...XC12345" clips.
    def commons_song(sci)
      query = ERB::Util.url_encode("#{sci} filetype:audio")
      res = get_json('https://commons.wikimedia.org/w/api.php?action=query&format=json' \
                     "&generator=search&gsrsearch=#{query}&gsrnamespace=6&gsrlimit=8" \
                     '&prop=imageinfo&iiprop=url%7Cmediatype')
      needle = sci.downcase.tr(' ', '_')
      match = Array(res&.dig('query', 'pages')&.values).find do |page|
        info = page.dig('imageinfo', 0)
        info && info['mediatype'] == 'AUDIO' &&
          page['title'].to_s.downcase.tr(' ', '_').include?(needle)
      end
      match&.dig('imageinfo', 0, 'url')
    end

    # A File: page title → its playable media URL.
    def file_url(title)
      info = get_json('https://en.wikipedia.org/w/api.php?action=query&format=json' \
                      "&prop=imageinfo&iiprop=url&titles=#{ERB::Util.url_encode(title)}")
      info&.dig('query', 'pages')&.values&.first&.dig('imageinfo', 0, 'url')
    end

    def get_json(url)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 8) do |http|
        http.get(uri.request_uri, 'User-Agent' => 'birdlife/1.0 (Connemara bird detector)')
      end
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    end

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
