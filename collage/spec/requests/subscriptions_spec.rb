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
      expect(response.body).to include('Alert delivery').and include("Species you're following")
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

    describe 'setting a delivery cadence' do
      def me = User.find_by(email: 'watcher@example.com')

      it 'creates a standing rule at the chosen cadence' do
        post '/subscriptions/cadence', params: { alert_type: 'rarity', cadence: 'digest' }
        expect(me.subscriptions.find_by(alert_type: 'rarity')).to have_attributes(cadence: 'digest', active: true)
      end

      it "removes a standing rule when set to 'off'" do
        me.subscriptions.create!(alert_type: 'rarity')
        expect { post '/subscriptions/cadence', params: { alert_type: 'rarity', cadence: 'off' } }.
          to change { me.subscriptions.where(alert_type: 'rarity').count }.by(-1)
      end

      it 'bulk-sets the cadence of every followed species, keeping the follows' do
        me.subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
        me.subscriptions.create!(alert_type: 'species', sci_name: 'Apus apus')
        post '/subscriptions/cadence', params: { alert_type: 'species', cadence: 'off' }
        expect(me.subscriptions.where(alert_type: 'species').pluck(:cadence)).to all(eq('off'))
        expect(me.subscriptions.where(alert_type: 'species').count).to eq(2) # still following
      end
    end
  end

  it 'unsubscribes via a token link without login' do
    sub = create(:user).subscriptions.create!(alert_type: 'species', sci_name: 'Crex crex')
    get "/subscriptions/#{sub.token}/unsubscribe"
    expect(response).to have_http_status(:ok)
    expect(sub.reload.active).to be(false)
  end
end
