require 'rails_helper'

RSpec.describe Station do
  describe '.language' do
    it 'defaults to Irish (the wall\'s voice)' do
      expect(described_class.language).to eq(:ga)
    end

    it 'reads the admin-set value from Setting' do
      described_class.language = :en
      expect(described_class.language).to eq(:en)
    end

    it 'rejects an unknown language rather than storing it' do
      expect { described_class.language = :fr }.to raise_error(ArgumentError)
    end

    it 'falls back safely if a bad value somehow lands in the store' do
      Setting.set(Station::LANGUAGE_SETTING, 'martian')
      expect(described_class.language).to eq(:ga)
    end
  end

  describe '.url' do
    it 'is the configured public site, not hard-coded' do
      expect(described_class.url).to eq('culfinbirds.net')
    end
  end
end
