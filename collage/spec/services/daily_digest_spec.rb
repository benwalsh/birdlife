require 'rails_helper'

RSpec.describe DailyDigest do
  let(:date) { Date.yesterday }

  before { allow(Notifier).to receive(:enabled?).and_return(true) }

  def digest_follower(sci)
    create(:user).tap { |u| u.subscriptions.create!(alert_type: 'species', sci_name: sci, cadence: 'digest') }
  end

  it 'sends one digest to a digest follower when their bird had an event that day' do
    user = digest_follower('Crex crex')
    create(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: date)
    expect(Notifier).to receive(:deliver_digest).with(hash_including(user: user, date: date)).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'bundles standing-rule events for a digest rule subscriber' do
    create(:user).subscriptions.create!(alert_type: 'rarity', cadence: 'digest')
    create(:event, event_type: 'rarity', sci_name: 'Crex crex', occurred_on: date)
    expect(Notifier).to receive(:deliver_digest).and_return(true)
    expect(described_class.deliver_all(date: date)).to eq(1)
  end

  it 'ignores immediate-cadence subscribers (already emailed live)' do
    create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex', cadence: 'immediate')
    create(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: date)
    expect(Notifier).not_to receive(:deliver_digest)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it 'is idempotent — a second run the same day sends nothing' do
    digest_follower('Crex crex')
    create(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: date)
    allow(Notifier).to receive(:deliver_digest).and_return(true)
    described_class.deliver_all(date: date)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end

  it "marks the day done even with nothing to send, so it won't rescan" do
    user = digest_follower('Crex crex') # no events for their bird
    expect(Notifier).not_to receive(:deliver_digest)
    described_class.deliver_all(date: date)
    expect(user.reload.last_digest_on).to eq(date)
  end

  it 'does nothing when alerts are disabled (no ALERTS_FROM)' do
    allow(Notifier).to receive(:enabled?).and_return(false)
    digest_follower('Crex crex')
    create(:event, event_type: 'species', sci_name: 'Crex crex', occurred_on: date)
    expect(described_class.deliver_all(date: date)).to eq(0)
  end
end
