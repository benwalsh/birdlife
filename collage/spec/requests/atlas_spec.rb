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

  it 'accepts each sort order' do
    %w[count recent alpha].each do |sort|
      get '/atlas', params: { sort: sort }
      expect(response).to have_http_status(:success)
    end
  end
end
