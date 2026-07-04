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

  # /station is the single Inky screen: one calm collage in the house style, run
  # through the e-ink preview filter. No rotation, no stats grid (that's /kiosk).
  describe 'GET /station' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders one collage screen, e-ink-framed, with no rotation scaffolding' do
      get '/station'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('<svg').and include('Spectra 6')
      expect(response.body).to include('id=\'eink\'').or include('id="eink"')
      expect(response.body).not_to include('name="station-screen"')
      expect(response.body).not_to include('stat-grid')
    end
  end

  # /kiosk is the passive-display surface: the four cards in the DOM at once,
  # cycled client-side by the kiosk Stimulus controller. No chrome.
  describe 'GET /kiosk' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create_list(:detection, 2, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    end

    it 'renders the four cards for the cycling display' do
      get '/kiosk'
      expect(response).to have_http_status(:success)
      expect(response.body.scan('data-kiosk-target').size).to eq(4)
      expect(response.body).to include('kiosk')       # the controller drives the cycle
      expect(response.body).to include('stat-grid')   # the numbers card lives here now
    end
  end
end
