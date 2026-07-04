require 'rails_helper'
require 'tmpdir'

RSpec.describe Almanac do
  describe '.weather_from' do
    it 'maps a WMO code to bilingual labels + emoji and rounds the temperature' do
      expect(described_class.weather_from(9.4, 3)).to eq(temp: 9, text: 'overcast', text_ga: 'modartha', emoji: '☁️')
    end

    it 'degrades gracefully for an unknown code' do
      expect(described_class.weather_from(12.0, 999)).to eq(temp: 12, text: '—', text_ga: '—', emoji: '🌡️')
    end
  end

  describe '.sun_from' do
    it 'pulls today\'s sunrise/sunset as HH:MM' do
      daily = { 'sunrise' => ['2026-07-03T05:12'], 'sunset' => ['2026-07-03T21:45'] }
      expect(described_class.sun_from(daily)).to eq(rise: '05:12', set: '21:45')
    end

    it 'is nil without both times' do
      expect(described_class.sun_from(nil)).to be_nil
      expect(described_class.sun_from('sunrise' => ['2026-07-03T05:12'])).to be_nil
    end
  end

  describe '.next_tide' do
    let(:times) { (10..14).map { |h| "2026-07-03T#{h}:00" } }
    let(:now) { Time.zone.parse('2026-07-03T10:30') }

    it 'finds the next high (a future local maximum), bilingually' do
      tide = described_class.next_tide(times, [1.0, 1.5, 2.0, 1.5, 1.0], now)
      expect(tide).to include(type: 'high', time: '12:00', label: 'High tide 12:00', label_ga: 'Lán mara 12:00')
    end

    it 'finds the next low (a future local minimum)' do
      tide = described_class.next_tide(times, [2.0, 1.5, 1.0, 1.5, 2.0], now)
      expect(tide).to include(type: 'low', label: 'Low tide 12:00', label_ga: 'Lag trá 12:00')
    end

    it 'ignores turning points already in the past' do
      # peak at 10:00 is before `now`; the next turning point is the 12:00 low
      tide = described_class.next_tide(times, [2.0, 1.5, 1.0, 1.5, 2.0], Time.zone.parse('2026-07-03T09:30'))
      expect(tide[:time]).to eq('12:00')
    end
  end

  describe '.place_from' do
    it 'picks the most-local name and appends the county' do
      addr = { 'village' => 'Tullycross', 'county' => 'County Galway', 'city' => 'Galway' }
      expect(described_class.place_from(addr)).to eq('Tullycross, County Galway')
    end

    it 'does not repeat a name that is both locality and county' do
      expect(described_class.place_from('city' => 'Dublin', 'county' => 'Dublin')).to eq('Dublin')
    end

    it 'is nil when there is nothing usable' do
      expect(described_class.place_from(nil)).to be_nil
      expect(described_class.place_from({})).to be_nil
    end
  end

  describe '.current' do
    let(:dir) { Pathname(Dir.mktmpdir) }
    let(:file) { dir.join('almanac.json') }

    before { stub_const('Almanac::STORE', file) }

    after { FileUtils.remove_entry(dir) if dir.exist? }

    it 'returns a blank reading when the cache file is missing' do
      expect(file).not_to exist
      expect(described_class.current).to eq(coords: nil, weather: nil, sun: nil, tide: nil, fetched_at: nil)
    end

    it 'reads back a cached reading and parses fetched_at' do
      file.write({
        coords:     { lat: 53.5, lon: -9.9, place: 'Culfin' },
        weather:    { temp: 11, text: 'overcast', emoji: '☁️' },
        tide:       { type: 'high', time: '14:30', label: 'High 14:30' },
        fetched_at: '2026-07-03T08:00:00Z'
      }.to_json)
      reading = described_class.current
      expect(reading[:weather][:temp]).to eq(11)
      expect(reading[:coords][:place]).to eq('Culfin')
      expect(reading[:fetched_at]).to be_a(ActiveSupport::TimeWithZone)
    end

    it 'survives a corrupt cache file' do
      file.write('{ not json')
      expect(described_class.current).to eq(coords: nil, weather: nil, sun: nil, tide: nil, fetched_at: nil)
    end
  end
end
