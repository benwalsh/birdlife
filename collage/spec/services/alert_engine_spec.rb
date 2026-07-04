require 'rails_helper'

RSpec.describe AlertEngine do
  before { allow(Notifier).to receive(:deliver).and_return(true) }

  describe '.scan' do
    it 'records a first_ever event for a species not detected before today' do
      expect { described_class.scan(['Crex crex']) }.
        to change { Event.where(event_type: 'first_ever', sci_name: 'Crex crex').count }.by(1)
    end

    it 'does not record first_ever when the species has older detections' do
      create(:detection, Sci_Name: 'Crex crex', Date: Date.yesterday)
      expect { described_class.scan(['Crex crex']) }.
        not_to(change { Event.where(event_type: 'first_ever').count })
    end

    it 'records a species event when someone is subscribed to it' do
      create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      create(:detection, Sci_Name: 'Crex crex', Date: Date.yesterday) # isolate from first_ever
      expect { described_class.scan(['Crex crex']) }.
        to change { Event.where(event_type: 'species', sci_name: 'Crex crex').count }.by(1)
    end

    it 'does not record a species event with no subscribers' do
      create(:detection, Sci_Name: 'Crex crex', Date: Date.yesterday)
      expect { described_class.scan(['Crex crex']) }.
        not_to(change { Event.where(event_type: 'species').count })
    end

    it 'is fire-once — scanning the same species twice keeps one event' do
      create(:subscription, sci_name: 'Crex crex')
      described_class.scan(['Crex crex'])
      expect { described_class.scan(['Crex crex']) }.not_to(change(Event, :count))
    end

    it 'delivers a pending species event to the matching subscriber and marks it notified' do
      sub = create(:subscription, alert_type: 'species', sci_name: 'Crex crex')
      create(:detection, Sci_Name: 'Crex crex', Date: Date.yesterday) # isolate the species event
      expect(Notifier).to receive(:deliver).
        with(event: an_instance_of(Event), subscription: sub).and_return(true)
      described_class.scan(['Crex crex'])
      expect(Event.find_by(event_type: 'species').notified_at).to be_present
    end

    it 'leaves an event unsent when delivery fails, so the next tick retries' do
      create(:subscription, sci_name: 'Crex crex')
      create(:detection, Sci_Name: 'Crex crex', Date: Date.yesterday)
      allow(Notifier).to receive(:deliver).and_return(false)
      described_class.scan(['Crex crex'])
      expect(Event.find_by(event_type: 'species').notified_at).to be_nil
    end
  end
end
