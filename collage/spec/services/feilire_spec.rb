require 'rails_helper'

RSpec.describe Feilire do
  describe '.for' do
    it 'returns the curated feast for a notable Irish saint\'s day' do
      entry = described_class.for(Date.new(2026, 7, 8)) # St Cillian
      expect(entry['kind']).to eq('saint')
      expect(entry['title']).to include('en' => 'Feast of St Cillian')
      expect(entry['gloss']['ga']).to be_present
    end

    it 'names the quarter-day at a cross-quarter date' do
      expect(described_class.for(Date.new(2026, 11, 1))['title']['en']).to eq('Samhain')
    end

    it 'falls back to the Celtic season on an ordinary day (Celtic seasons, not solstices)' do
      entry = described_class.for(Date.new(2026, 6, 20)) # no feast → summer
      expect(entry['kind']).to eq('season')
      expect(entry['title']).to include('en' => 'Summer')
      expect(entry['season']).to eq('samhradh')
    end
  end
end
