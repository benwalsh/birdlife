module StationProfileHelpers
  # A neutral, non-personal profile the suite can assert against — curated féilire days and
  # a lore entry with known, made-up content. birdlife's own specs test the MECHANISM against
  # this; assertions about real Irish content belong to the culfinbirds overlay's own suite.
  SAMPLE_PROFILE = Rails.root.join('spec/support/station_profiles/sample')

  # Run the example with STATION_PROFILE pointed at a fixture profile, restoring the previous
  # value and clearing StationProfile's cache on both sides, so the choice is isolated here.
  def with_station_profile(path)
    previous = ENV['STATION_PROFILE']
    ENV['STATION_PROFILE'] = path.to_s
    StationProfile.reset!
    yield
  ensure
    ENV['STATION_PROFILE'] = previous
    StationProfile.reset!
  end
end

RSpec.configure do |config|
  config.include StationProfileHelpers
  # Specs that don't opt into a fixture see the shipped stations/example; reset after each so a
  # leaked STATION_PROFILE (or cache) never bleeds across examples.
  config.after { StationProfile.reset! }
end
