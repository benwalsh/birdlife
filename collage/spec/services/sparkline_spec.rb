require 'rails_helper'

RSpec.describe Sparkline do
  describe '.paths' do
    it 'emits a smooth curve (cubic béziers, no vertical spikes) for real data' do
      counts = [0, 0, 1, 3, 8, 12, 9, 5, 4, 6, 10, 14, 11, 7, 5, 3, 2, 1, 0, 0, 1, 2, 3, 1]
      result = described_class.paths(counts)

      expect(result.path).to start_with('M ')
      expect(result.path).to include('C ') # smoothed, not straight L segments
      expect(result.path).not_to include(' L ') # the stroke is all curves
      # the fill re-uses the curve then closes to the baseline
      expect(result.fill).to start_with(result.path)
      expect(result.fill).to match(/ L [\d.]+ #{Sparkline::H} L [\d.]+ #{Sparkline::H} Z\z/o)
    end

    it 'rests as a flat gentle line (not a spike) when the day is silent' do
      result = described_class.paths(Array.new(24, 0))
      # a single straight segment near the baseline, no peaks
      expect(result.path).to match(/\AM \d/)
      expect(result.path).to include(' L ')
      expect(result.path).not_to include('C ')
    end

    it 'rests flat when given too few points to form a curve' do
      expect(described_class.paths([]).path).not_to include('C ')
      expect(described_class.paths([5]).path).not_to include('C ')
    end

    it 'keeps every coordinate inside the viewBox' do
      result = described_class.paths([0, 0, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0])
      coords = result.path.scan(/-?\d+\.?\d*/).map(&:to_f)
      xs = coords.each_slice(2).map(&:first)
      ys = coords.each_slice(2).map(&:last)
      expect(xs.min).to be >= 0
      expect(xs.max).to be <= Sparkline::W
      expect(ys.min).to be >= 0
      expect(ys.max).to be <= Sparkline::H
    end
  end

  describe 'blind spots (coverage → ghost)' do
    let(:busy) { Array.new(24, 5) }

    it 'has no ghost, and one continuous curve, when every bucket was covered' do
      result = described_class.paths(busy, coverage: Array.new(24, true))
      expect(result.ghost).to be_nil
      expect(result.path.scan('M ').size).to eq(1)
    end

    it 'ghosts a mic-down stretch on the baseline and breaks the curve around it' do
      coverage = Array.new(24, true)
      (8..15).each { |i| coverage[i] = false } # mic down mid-window
      result = described_class.paths(busy, coverage: coverage)

      base = Sparkline::H - Sparkline::PAD
      expect(result.ghost).to match(/\AM [\d.]+ #{base} L [\d.]+ #{base}\z/o) # a dotted baseline span
      expect(result.path.scan('M ').size).to eq(2)                            # curve split into two runs
    end

    it 'still marks a blind spot even when the covered part was silent' do
      coverage = Array.new(24, true)
      (0..5).each { |i| coverage[i] = false }
      result = described_class.paths(Array.new(24, 0), coverage: coverage)
      expect(result.ghost).to be_present # the resting line, but the outage is shown as unknown
    end

    it 'assumes full coverage (no ghost) when there is no coverage signal at all' do
      expect(described_class.paths(busy, coverage: nil).ghost).to be_nil
      expect(described_class.paths(busy, coverage: Array.new(24, false)).ghost).to be_nil
    end
  end
end
