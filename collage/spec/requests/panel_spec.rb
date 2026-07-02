require 'rails_helper'

RSpec.describe 'Panel' do
  # The bare 800x480 SVG the Inky shooter screenshots — no web chrome.
  it 'renders the SVG without the nav or window picker' do
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    get '/panel'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('<svg')
    expect(response.body).not_to include('window-pick')
    expect(response.body).not_to include('class=\'slider\'')
  end

  # The standalone Inky mock-up: a framed canvas + the Spectra-6 dither, client-side.
  it 'serves the emulator page with the panel canvas and Spectra-6 palette' do
    get '/emulator'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('id="panel"').and include('SPECTRA6')
    expect(response.body).to include('Inky Impression 7.3')
  end

  describe 'GET /station' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders each wall-station screen by name' do
      %w[collage stats focus general].each do |screen|
        get '/station', params: { screen: screen }
        expect(response).to have_http_status(:success)
        expect(response.body).to include(%(content="#{screen}"))
        expect(response.body).to include('Inky Impression 7.3')
      end
    end

    it 'falls back to the slow rotation when the screen name is unknown' do
      get '/station', params: { screen: 'dashboard' }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('name="station-screen"')
      expect(response.body).not_to include('content="dashboard"')
    end
  end

  describe 'GET /station/next' do
    it 'returns the next screen in the station programme' do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      get '/station/next'

      expect(response).to have_http_status(:success)
      payload = JSON.parse(response.body)
      expect(payload).to include('screen' => 'stats', 'dwell_seconds' => 300, 'url' => '/station?screen=stats')
    end
  end
end
