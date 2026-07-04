require 'rails_helper'

RSpec.describe 'Subscriptions' do
  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'sub-1',
      info: { email: 'watcher@example.com', name: 'Watcher', image: 'https://example.com/a.png' }
    )
  end

  def sign_in
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config['omniauth.auth'] = auth
    get '/auth/google_oauth2/callback'
  end

  after do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  it 'redirects the account page home when signed out' do
    get '/account'
    expect(response).to redirect_to('/')
  end

  context 'when signed in' do
    before { sign_in }

    it 'renders the account page' do
      get '/account'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Alerts')
    end

    it 'creates a species subscription' do
      expect do
        post '/subscriptions', params: { subscription: { alert_type: 'species', sci_name: 'Crex crex' } }
      end.to change(Subscription, :count).by(1)
      expect(User.find_by(email: 'watcher@example.com').subscriptions.first.sci_name).to eq('Crex crex')
    end

    it 'removes a subscription' do
      sub = User.find_by(email: 'watcher@example.com').
            subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
      expect { delete "/subscriptions/#{sub.id}" }.to change(Subscription, :count).by(-1)
    end
  end

  it 'unsubscribes via a token link without login' do
    sub = create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
    get "/subscriptions/#{sub.token}/unsubscribe"
    expect(response).to have_http_status(:ok)
    expect(sub.reload.active).to be(false)
  end
end
