require 'rails_helper'

RSpec.describe 'Species' do
  before do
    # Pre-seed the description cache so the request never touches Wikipedia.
    # fetched_ga_at marks the Irish lookup as already attempted (no article).
    SpeciesInfo.create!(
      sci_name:      'Erithacus rubecula',
      description:   'A small insectivorous passerine.',
      fetched_ga_at: Time.current
    )
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin', Confidence: 0.91)
  end

  it 'renders the detail panel as a turbo-frame with bilingual names and stats' do
    get species_path('Erithacus rubecula')

    expect(response).to have_http_status(:success)
    expect(response.body).to include('turbo-frame').and include('id="detail"')
    expect(response.body).to include('Spideog').and include('European Robin').and include('Erithacus rubecula')
    expect(response.body).to include('all time').and include('today').and include('first heard')
  end

  it 'shows the cached description and the species\' recordings' do
    get species_path('Erithacus rubecula')

    expect(response.body).to include('A small insectivorous passerine.')
    expect(response.body).to include('Detections').and include('91%')
  end

  it 'links out to Wikipedia and eBird' do
    get species_path('Erithacus rubecula')

    expect(response.body).to include('en.wikipedia.org/wiki/Erithacus_rubecula')
    expect(response.body).to include('ebird.org/search')
  end
end
