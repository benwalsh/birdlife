# The public cloud mirror (App Runner behind CloudFront), on RDS MySQL. It's
# production with a few flips, so inherit production.rb wholesale and override
# only what differs — the Pi is a plain-HTTP LAN appliance that serves its own
# assets; the cloud sits behind TLS-terminating CloudFront and an S3/CDN asset
# host. Keeping this DRY means production tuning stays in one place.
require_relative 'production'

Rails.application.configure do
  # CloudFront terminates TLS and forwards plain HTTP to App Runner; trust it and
  # force HTTPS (the opposite of the Pi, which has no TLS in front).
  config.assume_ssl = true
  config.force_ssl = true

  # First cut: the container serves its own static assets (digested JS/CSS under
  # /assets, the Vite bundle under /vite, the bird PNGs under /birds) and
  # CloudFront caches them in front. Later optimisation to slim the image —
  # offload the ~225 MB of illustrations to S3: set RAILS_SERVE_STATIC_FILES=false
  # and point ASSET_HOST at the CDN.
  config.public_file_server.enabled = ENV.fetch('RAILS_SERVE_STATIC_FILES', 'true') == 'true'
  config.asset_host = ENV['ASSET_HOST'] if ENV['ASSET_HOST'].present?
end
