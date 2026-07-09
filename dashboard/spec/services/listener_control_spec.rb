require 'rails_helper'

RSpec.describe ListenerControl do
  describe '.restart' do
    it 'is a safe no-op where the unit/systemctl is not installed (macOS dev, cloud)' do
      allow(described_class).to receive(:available?).and_return(false)
      result = described_class.restart
      expect(result[:ok]).to be(false)
      expect(result[:message]).to match(/unavailable/)
    end

    it 'restarts the unit via non-interactive sudo when available' do
      allow(described_class).to receive(:available?).and_return(true)
      expect(described_class).to receive(:system).with('sudo', '-n', 'systemctl', 'restart', described_class::UNIT).and_return(true)
      expect(described_class.restart).to include(ok: true)
    end

    it 'reports failure (not a crash) when the restart command fails' do
      allow(described_class).to receive(:available?).and_return(true)
      allow(described_class).to receive(:system).and_return(false)
      expect(described_class.restart).to include(ok: false)
    end
  end
end
