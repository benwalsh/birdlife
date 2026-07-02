require 'rails_helper'

RSpec.describe 'Atlas' do
  before do
    create(:detection, Sci_Name: 'Erithacus rubecula', Com_Name: 'European Robin')
    create(:detection, Sci_Name: 'Pyrrhocorax pyrrhocorax', Com_Name: 'Red-billed Chough')
  end

  it 'lists a card per species with the Irish name' do
    get '/atlas'
    expect(response).to have_http_status(:success)
    expect(response.body.scan('bird-card').size).to eq(2)
    expect(response.body).to include('Spideog').and include('Cág cosdearg')
  end

  it 'marks each card with its BoCCI conservation status dot' do
    get '/atlas'
    # Robin is Green-listed, Chough is Amber-listed
    expect(response.body).to include('cons-dot green').and include('cons-dot amber')
  end

  it 'accepts each sort order' do
    %w[count recent alpha].each do |sort|
      get '/atlas', params: { sort: sort }
      expect(response).to have_http_status(:success)
    end
  end

  describe 'all-species scope' do
    it 'shows the whole illustrated library, with un-heard birds greyed but present' do
      get '/atlas', params: { scope: 'all' }
      expect(response).to have_http_status(:success)
      expect(response.body.scan('bird-card').size).to eq(SpeciesCatalog.all_sci.size)
      expect(response.body).to include('bird-card unseen').and include('not yet heard')
      # a bird we ship art for but have never detected
      expect(response.body).to include('Iolar firéan')
    end

    it 'sorts the all-species view in every order (count is an Integer, not a collection)' do
      %w[count recent alpha].each do |sort|
        get '/atlas', params: { scope: 'all', sort: sort }
        expect(response).to have_http_status(:success)
      end
    end
  end
end
