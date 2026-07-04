require 'rails_helper'

RSpec.describe 'Ingest' do
  let(:token) { 'sekret-ingest-token' }
  let(:rows) do
    [
      { Date: '2026-07-02', Time: '22:00:00', Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin',
        Confidence: 0.91, Lat: 53.55, Lon: -9.92, Week: 27, File_Name: 'a.wav', dedupe_key: 'key-a' },
      { Date: '2026-07-02', Time: '22:01:00', Sci_Name: 'Pica pica', Com_Name: 'Eurasian Magpie',
        Confidence: 0.88, Lat: 53.55, Lon: -9.92, Week: 27, File_Name: 'a.wav', dedupe_key: 'key-b' }
    ]
  end

  def ingest(body, bearer: token)
    headers = bearer ? { 'Authorization' => "Bearer #{bearer}" } : {}
    post '/ingest/detections', params: { detections: body }, headers: headers, as: :json
  end

  context 'when CLOUD_INGEST_TOKEN is unset (the Pi)' do
    it 'is disabled (404) so it never accepts writes' do
      ingest(rows)
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when a token is configured (the cloud)' do
    around do |example|
      ENV['CLOUD_INGEST_TOKEN'] = token
      example.run
    ensure
      ENV.delete('CLOUD_INGEST_TOKEN')
    end

    # Ingest fires the LLM "today" refresh; stub it so tests never dial Bedrock.
    before { allow(TodaySummary).to receive(:refresh_if_stale) }

    it 'refreshes the today summary once a batch lands' do
      expect(TodaySummary).to receive(:refresh_if_stale)
      ingest(rows)
    end

    it 'rejects a missing or wrong bearer token' do
      ingest(rows, bearer: nil)
      expect(response).to have_http_status(:unauthorized)
      ingest(rows, bearer: 'wrong')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'upserts the batch' do
      expect { ingest(rows) }.to change(Detection, :count).by(2)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['upserted']).to eq(2)
      expect(Detection.find_by(dedupe_key: 'key-a').Sci_Name).to eq('Erithacus rubecula')
    end

    it 'is idempotent — re-POSTing the same batch adds nothing' do
      ingest(rows)
      expect { ingest(rows) }.not_to change(Detection, :count)
    end

    it 'skips rows without a dedupe_key' do
      expect { ingest([rows.first.except(:dedupe_key)]) }.not_to change(Detection, :count)
    end
  end
end
