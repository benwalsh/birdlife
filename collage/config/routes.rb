Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'collage#show'

  # Google sign-in (OmniAuth). The request phase (POST /auth/google_oauth2) is
  # handled by the OmniAuth middleware; Google returns to the callback.
  get 'auth/:provider/callback' => 'sessions#create'
  get 'auth/failure' => 'sessions#failure'
  delete 'logout' => 'sessions#destroy', as: :logout

  # Alert subscriptions: logged-in users manage their own ("email me if you hear a
  # Corncrake"). Unsubscribe is token-authed (the one-click email link), no login.
  get    'account' => 'subscriptions#index', as: :account
  post   'subscriptions' => 'subscriptions#create'
  delete 'subscriptions/:id' => 'subscriptions#destroy', as: :subscription
  get    'subscriptions/:token/unsubscribe' => 'subscriptions#unsubscribe', as: :unsubscribe

  # The Pi's lazy push lands here (cloud mirror only; 404 on the Pi). Token-authed.
  post 'ingest/detections' => 'ingest#detections'

  # JSON API for the React SPA (and, later, api.culfinbirds.net). Read-only GETs.
  namespace :api do
    get 'overview' => 'overview#show'
    get 'stats' => 'stats#show'
    get 'directory' => 'directory#show'
    get 'species/:sci' => 'species#show', constraints: { sci: %r{[^/]+} }
  end

  get 'panel' => 'collage#panel'
  # The three surfaces, "opposite of mobile-first" — richest at the root, more
  # constrained as they specialise:
  #   /        the full experience (chrome + nav) — see root above
  #   /kiosk   no chrome, the four cards cycling, for a passive monitor/iPad
  #   /station the single collage screen in the house style, tuned for the Inky
  get 'kiosk' => 'collage#kiosk'
  get 'station' => 'collage#station'
  # A browser mock-up of the physical Inky Impression 7.3" panel: fetches /panel
  # and applies the same Spectra-6 dither the real glass gets.
  get 'emulator' => 'collage#emulator'
  # Stats, the species directory, and species detail are now tabs + a modal inside
  # the React SPA at `/`, served by /api/stats, /api/directory, /api/species/:sci.
end
