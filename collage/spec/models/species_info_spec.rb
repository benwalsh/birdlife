require 'rails_helper'

RSpec.describe SpeciesInfo do
  describe '.english_for' do
    it 'returns a cached description without fetching' do
      described_class.create!(sci_name: 'Erithacus rubecula', description: 'Cached prose.')
      expect(described_class).not_to receive(:fetch)

      expect(described_class.english_for('Erithacus rubecula')).to eq('Cached prose.')
    end

    it 'fetches once, then caches for subsequent calls' do
      # .once fails the spec if the cache miss isn't honoured on the second call.
      expect(described_class).to receive(:fetch).once.and_return('Fresh prose.')

      expect(described_class.english_for('Turdus merula', 'Common Blackbird')).to eq('Fresh prose.')
      expect(described_class.find_by(sci_name: 'Turdus merula').description).to eq('Fresh prose.')
      expect(described_class.english_for('Turdus merula')).to eq('Fresh prose.')
    end
  end

  describe '.irish_for' do
    it 'returns nil without fetching when the bird has no Irish name' do
      expect(described_class).not_to receive(:fetch)

      expect(described_class.irish_for('Turdus merula', nil)).to be_nil
    end

    it 'fetches by the Irish name and remembers a miss so it is not retried' do
      # Most birds lack an Irish article; fetched_ga_at must cache the miss.
      expect(described_class).to receive(:fetch).once.and_return(nil)

      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to be_nil
      expect(described_class.irish_for('Turdus merula', 'Lon dubh')).to be_nil
    end
  end
end
