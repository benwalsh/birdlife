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

  # Assets (digested JS/CSS + the bird PNGs under /birds) are served by S3 +
  # CloudFront, not by Rails — so don't serve static files from the container,
  # and point asset URLs at the CDN. ASSET_HOST is the CloudFront asset domain.
  config.public_file_server.enabled = false
  config.asset_host = ENV['ASSET_HOST'] if ENV['ASSET_HOST'].present?
end
