# Google sign-in. Credentials come from the environment (never committed) — set
# GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET, and register the callback URL
# (<host>/auth/google_oauth2/callback) in the Google Cloud console.
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           ENV.fetch('GOOGLE_CLIENT_ID', nil),
           ENV.fetch('GOOGLE_CLIENT_SECRET', nil),
           scope:  'email,profile',
           prompt: 'select_account'
end

OmniAuth.config.logger = Rails.logger
# Redirect (don't raise) if a sign-in is abandoned or fails.
OmniAuth.config.on_failure = proc do |env|
  SessionsController.action(:failure).call(env)
end

# Dev-only convenience: FAKE_LOGIN=1 mocks the Google round-trip so the admin UI
# can be built and previewed locally without real credentials. Never active
# outside development.
if Rails.env.development? && ENV['FAKE_LOGIN'].present?
  OmniAuth.config.test_mode = true
  OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
    provider: 'google_oauth2',
    uid:      'dev-001',
    info:     { email: 'ben@dalymount.com', name: 'Ben Walsh', image: nil }
  )
end
