require 'rails_helper'

RSpec.describe Enrichment::SourceFetcher do
  subject(:fetcher) { described_class.new(sci_name: 'Cuculus canorus', run_id: 'run-1') }

  describe '#trusted?' do
    it 'accepts exact trusted hosts and BirdWatch county affiliates' do
      expect(fetcher.trusted?('duchas.ie')).to be(true)
      expect(fetcher.trusted?('birdwatchireland.ie')).to be(true)
      expect(fetcher.trusted?('birdwatchgalway.org')).to be(true) # discovered affiliate
      expect(fetcher.trusted?('en.wikipedia.org')).to be(true)
    end

    it 'refuses anything off the allowlist' do
      expect(fetcher.trusted?('example.com')).to be(false)
      expect(fetcher.trusted?('evil-birdwatchireland.ie.attacker.com')).to be(false)
      expect(fetcher.trusted?(nil)).to be(false)
    end
  end

  # Stubbing the fetcher's own http_get is the network boundary — there's no webmock
  # in this project, and it's exactly what a unit test of the allowlist/logging wants.
  # rubocop:disable RSpec/SubjectStub
  describe '#fetch' do
    it 'refuses an untrusted URL without a request or a log row' do
      expect(fetcher).not_to receive(:http_get)
      result = fetcher.fetch('https://example.com/cuckoo')
      expect(result).to include(error: a_string_matching(/untrusted host/))
      expect(SourceFetchLog.count).to eq(0)
    end

    it 'fetches a trusted URL, strips it to text, and logs exactly one hit' do
      html = '<html><body><script>x()</script><p>Cuckoos are brood parasites.</p></body></html>'
      allow(fetcher).to receive(:http_get).and_return(html)
      result = fetcher.fetch('https://www.duchas.ie/en/cbes/1')
      expect(result[:text]).to eq('Cuckoos are brood parasites.')
      expect(result[:host]).to eq('www.duchas.ie')
      expect(SourceFetchLog.count).to eq(1)
      expect(SourceFetchLog.last).to have_attributes(host: 'www.duchas.ie', sci_name: 'Cuculus canorus')
    end

    it 'returns an error (no raise, no log) when the request fails' do
      allow(fetcher).to receive(:http_get).and_return(nil)
      result = fetcher.fetch('https://duchas.ie/x')
      expect(result).to include(:error)
      expect(SourceFetchLog.count).to eq(0)
    end
  end
  # rubocop:enable RSpec/SubjectStub
end
