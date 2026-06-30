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
end
