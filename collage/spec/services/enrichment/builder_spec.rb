require 'rails_helper'

RSpec.describe Enrichment::Builder do
  let(:date) { Date.new(2026, 7, 4) }
  let(:sci)  { 'Aegithalos caudatus' }
  let(:url)  { 'https://en.wikipedia.org/wiki/Long-tailed_tit' }

  # Fake Converse content items exposing the .text / .tool_use accessors the builder
  # reads, and the response's stop_reason + output.message.content.
  def text_item(str) = double(text: str, tool_use: nil)
  def response(stop, items) = double(stop_reason: stop, output: double(message: double(content: items)))

  def use_item(id, src)
    double(text: nil, tool_use: double(tool_use_id: id, name: 'fetch_source', input: { 'url' => src }))
  end

  before do
    allow(Bedrock).to receive(:disabled?).and_return(false)
    # The one real network boundary — everything else in SourceFetcher runs for real
    # (trusted-host check, the source_fetch_log write, text extraction).
    allow_any_instance_of(Enrichment::SourceFetcher).to receive(:http_get).
      and_return('<html><body><p>Long-tailed tits build a domed nest of moss and feathers.</p></body></html>')
  end

  it 'sources cited blocks from a fetched page and stores them as one bundle' do
    final = [
      { type: 'fact', id: 'nest', text: 'They build a domed nest of moss and feathers.',
        sources: [{ host: 'en.wikipedia.org', url: url }] },
      { type: 'folklore', id: 'bottle', gated: true, text: 'It was once called the bottle-tit for its nest.',
        sources: [{ host: 'en.wikipedia.org', url: url }] }
    ].to_json
    allow(Bedrock).to receive(:converse_tools).and_return(
      response('tool_use', [use_item('t1', url)]),
      response('end_turn', [text_item(final)])
    )

    bundle = described_class.build_one(date: date, sci_name: sci)

    expect(bundle).to be_persisted
    expect(bundle.block_objects.map(&:type)).to contain_exactly('fact', 'folklore')
    expect(SourceFetchLog.where(sci_name: sci)).to be_present
  end

  it 'drops a block whose citation was never actually fetched (no fabricated sources)' do
    final = [
      { type: 'fact', id: 'real', text: 'A domed nest of moss.', sources: [{ host: 'en.wikipedia.org', url: url }] },
      { type: 'fact', id: 'fake', text: 'An invented claim.',
        sources: [{ host: 'en.wikipedia.org', url: 'https://en.wikipedia.org/wiki/Never_fetched' }] }
    ].to_json
    allow(Bedrock).to receive(:converse_tools).and_return(
      response('tool_use', [use_item('t1', url)]),
      response('end_turn', [text_item(final)])
    )

    expect(described_class.build_one(date: date, sci_name: sci).block_objects.map(&:id)).to eq(['real'])
  end

  it 'stores nothing (nil) when no block survives validation' do
    allow(Bedrock).to receive(:converse_tools).and_return(response('end_turn', [text_item('[]')]))
    expect(described_class.build_one(date: date, sci_name: sci)).to be_nil
    expect(EnrichmentBundle.where(sci_name: sci)).to be_empty
  end
end
