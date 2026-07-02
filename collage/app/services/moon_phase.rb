# The moon's phase for a given date — a pure astronomical calculation (no API),
# since the phase is the same the world over. Good enough for a wall display:
# the age since a known new moon, folded over the synodic month, gives both a
# named phase and an illumination percentage.
class MoonPhase
  SYNODIC = 29.530588853                 # days between new moons
  KNOWN_NEW_MOON = Date.new(2000, 1, 6)  # a reference new moon
  NAMES = [
    'New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
    'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent'
  ].freeze

  Phase = Data.define(:name, :illumination)

  class << self
    def for(date = Date.current)
      age = (date - KNOWN_NEW_MOON).to_f % SYNODIC
      index = ((age / SYNODIC) * 8).round % 8
      illumination = (((1 - Math.cos(2 * Math::PI * age / SYNODIC)) / 2) * 100).round
      Phase.new(name: NAMES[index], illumination: illumination)
    end
  end
end
