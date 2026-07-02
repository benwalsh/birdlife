require 'rails_helper'

RSpec.describe 'Species' do
  before do
    # Pre-seed the cache so the request never touches Wikipedia. The fetched_*_at
    # timestamps mark each lookup as already attempted (Irish article absent, song
    # present), so the controller serves the cached values without a network call.
    SpeciesInfo.create!(
      sci_name:        'Erithacus rubecula',
      description:     'A small insectivorous passerine.',
      fetched_ga_at:   Time.current,
      song_url:        'https://upload.wikimedia.org/wikipedia/commons/7/74/Robin.ogg',
      fetched_song_at: Time.current
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

  it 'plays a song sample inline and links out to Wikipedia and eBird' do
    get species_path('Erithacus rubecula')

    expect(response.body).to include('data-controller="song"')
    expect(response.body).to include('<audio').and include('commons/7/74/Robin.ogg')
    expect(response.body).to include('en.wikipedia.org/wiki/Erithacus_rubecula')
    expect(response.body).to include('ebird.org/search')
  end

  it 'shows the Irish (BoCCI) conservation status' do
    get species_path('Erithacus rubecula') # Robin is Green-listed

    expect(response.body).to include('cons-line green')
    expect(response.body).to include('Green list')
  end
end
