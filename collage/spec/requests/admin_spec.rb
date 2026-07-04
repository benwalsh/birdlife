require 'rails_helper'

RSpec.describe 'Admin' do
  let(:auth) do
    OmniAuth::AuthHash.new(
      provider: 'google_oauth2', uid: 'admin-1',
      info: { email: 'boss@example.com', name: 'Boss', image: nil }
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

  it 'bounces anonymous visitors home' do
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'bounces signed-in non-admins home (fail-closed)' do
    sign_in # not in ADMIN_EMAILS
    get '/admin'
    expect(response).to redirect_to('/')
  end

  it 'renders the health panel for admins' do
    allow_any_instance_of(User).to receive(:admin?).and_return(true)
    sign_in
    get '/admin'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Listening').and include('Alerts').and include('System')
  end
end
