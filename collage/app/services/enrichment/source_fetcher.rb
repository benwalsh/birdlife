require 'net/http'

module Enrichment
  # The fetch tool Stage 1 (Claude, via Bedrock tool-use) calls to source from trusted
  # hosts — the ONLY path the enrichment pass takes to the network. It:
  #   - refuses any host off the trusted allowlist (returns an error, makes no request);
  #   - logs every real outbound hit to source_fetch_log (the politeness ledger);
  #   - returns readable plain text (Nokogiri-stripped) for the model to cite.
  # A URL the model wants but can't be trusted is refused, not fetched — the block that
  # would have needed it is simply dropped upstream. Never raises out; returns an error
  # hash the model can react to.
  class SourceFetcher
    # Exact trusted hosts. BirdWatch Ireland county branches are matched by pattern
    # (discovered dynamically — e.g. birdwatchgalway.org — not hardcoded one by one).
    TRUSTED_HOSTS = %w[
      birdwatchireland.ie www.birdwatchireland.ie
      biodiversityireland.ie maps.biodiversityireland.ie
      irbc.ie iwt.ie
      duchas.ie www.duchas.ie celt.ucc.ie irishheritagenews.ie
      en.wikipedia.org
    ].freeze
    AFFILIATE = /\Abirdwatch[a-z]+\.(?:ie|org)\z/
    MAX_CHARS = 4000
    USER_AGENT = 'birdlife/1.0 (Eist bird detector; enrichment)'.freeze
    # The Irish heritage sources (dúchas.ie, CELT) answer with a 301 before serving the
    # page, so we MUST follow redirects or they always read as "fetch failed" and the model
    # falls back to Wikipedia. Bounded, and every hop is re-checked against the allowlist so
    # a redirect can't smuggle the fetch off to an untrusted host.
    MAX_REDIRECTS = 4

    def initialize(sci_name:, run_id:)
      @sci_name = sci_name
      @run_id = run_id
    end

    # { host:, url:, text: } on success, or { error: } — never raises.
    def fetch(url)
      host = host_of(url)
      return { error: "untrusted host: #{host}" } unless trusted?(host)

      body = http_get(url)
      return { error: "fetch failed: #{url}" } unless body

      log!(host, url)
      { host: host, url: url, text: extract_text(body) }
    rescue StandardError => e
      { error: "#{e.class}: #{e.message}" }
    end

    def trusted?(host)
      return false if host.blank?

      TRUSTED_HOSTS.include?(host) || AFFILIATE.match?(host)
    end

    private

    def host_of(url)
      URI.parse(url.to_s).host&.downcase
    rescue URI::InvalidURIError
      nil
    end

    def http_get(url, redirects_left: MAX_REDIRECTS)
      uri = URI(url)
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                            open_timeout: 5, read_timeout: 12) do |http|
        http.get(uri.request_uri, 'User-Agent' => USER_AGENT)
      end

      case res
      when Net::HTTPSuccess then res.body
      when Net::HTTPRedirection then follow(res['location'], uri, redirects_left)
      end
    end

    # Follow a redirect only to another TRUSTED host (a redirect must never be a way off
    # the allowlist), resolving relative Location headers against the current URL.
    def follow(location, base, redirects_left)
      return nil if location.blank? || redirects_left <= 0

      target = URI.join(base, location)
      return nil unless trusted?(target.host&.downcase)

      http_get(target.to_s, redirects_left: redirects_left - 1)
    rescue URI::InvalidURIError
      nil
    end

    def extract_text(html)
      doc = Nokogiri::HTML(html)
      doc.search('script, style, nav, header, footer').remove
      doc.text.gsub(/\s+/, ' ').strip.first(MAX_CHARS)
    end

    def log!(host, url)
      SourceFetchLog.create!(host: host, url: url, sci_name: @sci_name,
                             fetched_at: Time.current, run_id: @run_id)
    end
  end
end
