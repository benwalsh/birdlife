require 'rails_helper'

RSpec.describe Event do
  it 'is pending until notified' do
    event = create(:event)
    expect(described_class.pending).to include(event)
    event.mark_notified!
    expect(described_class.pending).not_to include(event)
  end

  it 'fires once per type + species + day (unique index)' do
    create(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: Date.current)
    dup = build(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: Date.current)
    expect { dup.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  # The kind label is the shared "news" wording the wall, the site strip and the email
  # all read from — one source, so the three surfaces never drift apart.
  it 'names each newsworthy kind bilingually' do
    expect(described_class.new(event_type: 'rarity').kind_label).to eq(en: 'Rarity', ga: 'Annamh')
    expect(described_class.new(event_type: 'first_ever').kind_label).to eq(en: 'First ever', ga: 'Céaduair riamh')
    expect(described_class.new(event_type: 'seasonal').kind_label).to eq(en: 'Seasonal return', ga: 'Filleadh séasúrach')
  end
end
