require 'rails_helper'

RSpec.describe 'Collage' do
  describe 'GET /' do
    before do
      travel_to Time.zone.local(2026, 6, 29, 9, 0)
      create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
      create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
      create(:detection, Sci_Name: 'Pyrrhocorax pyrrhocorax', Com_Name: 'Red-billed Chough')
    end

    it 'returns http success' do
      get '/'
      expect(response).to have_http_status(:success)
    end

    it 'carries each bird\'s bilingual name + windowed count for the caption' do
      get '/'
      # The caption pill is JS-populated on hover; the data rides on the birds.
      expect(response.body).to include('Spideog')      # data-ga (Erithacus)
      expect(response.body).to include('Cág cosdearg') # data-ga (Pyrrhocorax)
      expect(response.body).to include('collage-tip')  # the (empty) caption pill
    end

    it 'renders a bird per species' do
      get '/'
      expect(response.body.scan('collage__bird').size).to eq(2)
    end
  end
end
