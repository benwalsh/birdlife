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
  get 'panel' => 'collage#panel'
  # The Éist "Listening Station" view — the Inky-first base tier (480x800 portrait
  # on the wall). Standalone for now while the design settles; will become the
  # base the desktop chrome grows around, and the shooter/emulator target.
  get 'station' => 'collage#station'
  get 'station/next' => 'collage#station_next'
  # A browser mock-up of the physical Inky Impression 7.3" panel: fetches /panel
  # and applies the same Spectra-6 dither the real glass gets.
  get 'emulator' => 'collage#emulator'
  get 'stats' => 'stats#show'
  get 'atlas' => 'atlas#show'
  # Scientific names carry spaces/dots, so allow anything but a slash.
  get 'species/:sci', to: 'species#show', as: :species, constraints: { sci: %r{[^/]+} }
end
