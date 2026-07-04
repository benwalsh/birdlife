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
end
