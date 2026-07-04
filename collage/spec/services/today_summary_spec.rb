require 'rails_helper'
require 'tmpdir'

RSpec.describe TodaySummary do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:file) { dir.join('today_summary.json') }

  # A fixed facts object so these tests exercise only the summary layer (prompting,
  # caching, validation, fallback) — never the DailyFacts engine or the database.
  let(:facts) do
    {
      date: '2026-07-03', species_today: 3, detections_today: 42,
      items: [
        { common_name: 'Common Greenshank', irish_name: 'Laidhrín glas', call_count: 1,
          importance: 100, flags: %w[all_time_first] },
        { common_name: 'House Sparrow', irish_name: 'Gealbhan binne', call_count: 30,
          importance: 5, flags: %w[routine most_common] }
      ],
      spotlight: { common_name: 'Common Greenshank', irish_name: 'Laidhrín glas',
                   rarity_context: 'first record at the station', blurb: 'A wading bird.' },
      activity_note: 'quieter_than_typical'
    }
  end

  before do
    stub_const('TodaySummary::STORE', file)
    allow(DailyFacts).to receive(:for).and_return(facts)
  end

  after { FileUtils.remove_entry(dir) if dir.exist? }

  describe '.user_message' do
    it 'serialises the facts object into the prompt the model sees' do
      msg = described_class.user_message(facts)
      expect(msg).to include('3 species, 42 detections today')
      expect(msg).to include('Common Greenshank (Laidhrín glas), 1, importance 100, [all_time_first]')
      expect(msg).to include('Activity: quieter than typical.')
      expect(msg).to include('Spotlight: Common Greenshank — first record at the station.')
      expect(msg).to include('Background: A wading bird.')
    end
  end

  describe '.current' do
    it 'synthesises the template when there is no cache' do
      result = described_class.current(facts: facts)
      expect(result[:source]).to eq('template')
      expect(result[:bullets].first).to eq('3 species and 42 detections logged today.')
    end
  end

  describe '.refresh_if_stale' do
    before { allow(Bedrock).to receive(:disabled?).and_return(true) } # template path — no network

    it 'refreshes when there is no cache yet' do
      expect { described_class.refresh_if_stale }.to change(file, :exist?).from(false).to(true)
    end

    it 'skips the refresh when the cache is fresh' do
      described_class.refresh
      expect(described_class).not_to receive(:refresh)
      described_class.refresh_if_stale
    end
  end

  describe '.refresh' do
    context 'when the LLM is disabled' do
      before { allow(Bedrock).to receive(:disabled?).and_return(true) }

      it 'writes the deterministic template to the cache' do
        result = described_class.refresh
        expect(result[:source]).to eq('template')
        expect(file).to exist
        expect(described_class.current[:source]).to eq('template')
      end
    end

    context 'when the LLM returns good bullets' do
      before do
        allow(Bedrock).to receive_messages(
          disabled?: false,
          converse:  "- A Common Greenshank (Laidhrín glas) was heard for the first time.\n" \
                     '- The usual sparrows made up the rest of a quiet day.'
        )
      end

      it 'caches the narrated summary and reads it back' do
        result = described_class.refresh
        expect(result[:source]).to eq('llm')
        expect(result[:bullets].size).to eq(2)
        expect(described_class.current[:bullets].first).to include('Greenshank')
      end
    end

    context 'when the model output breaks a house rule' do
      before do
        allow(Bedrock).to receive_messages(disabled?: false,
                                           converse:  '- A busy, thriving day for birdlife!')
      end

      it 'rejects it and falls through to the template (no cache yet)' do
        expect(described_class.refresh[:source]).to eq('template')
      end
    end

    context 'when generation fails but a good summary is already cached' do
      before { allow(Bedrock).to receive(:disabled?).and_return(false) }

      it 'keeps the last-good cache rather than overwriting it' do
        allow(Bedrock).to receive(:converse).and_return("- First good line.\n- Second good line.")
        described_class.refresh

        allow(Bedrock).to receive(:converse).and_raise(Seahorse::Client::NetworkingError.new(StandardError.new('down')))
        result = described_class.refresh

        expect(result[:source]).to eq('llm')
        expect(result[:bullets]).to eq(['First good line.', 'Second good line.'])
      end
    end
  end
end
