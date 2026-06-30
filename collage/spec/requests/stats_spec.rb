require 'rails_helper'

RSpec.describe 'Stats' do
  before do
    travel_to Time.zone.local(2026, 6, 29, 12, 0)
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    create(:detection, Sci_Name: 'Turdus merula', Com_Name: 'Eurasian Blackbird')
  end

  it 'renders the stats view with its sections' do
    get '/stats'
    expect(response).to have_http_status(:success)
    expect(response.body).to include('Most Heard').and include('By Period').and include('First Detections')
  end

  it 'shows the loudest species first in Irish' do
    get '/stats'
    expect(response.body.index('Spideog')).to be < response.body.index('Lon dubh')
  end

  it 'accepts a time-window param' do
    get '/stats', params: { h: 1 }
    expect(response).to have_http_status(:success)
  end
end
