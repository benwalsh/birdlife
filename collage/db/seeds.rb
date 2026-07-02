# Sample Connemara morning for desktop development — no Pi, no mic, no birds.db.
# A mix of garden, coastal, bog and moorland species. Idempotent: clears and
# reseeds today's detections each run.

# Local dev/test only. On the Pi (production) detections come from the live mic
# via the listener; in the cloud mirror they arrive via ingest from the Pi —
# neither must have fake birds injected by db:prepare.
unless Rails.env.local?
  puts "seeds: skipped in #{Rails.env} (real detections come from the listener/ingest)" # rubocop:disable Rails/Output
  return
end

SAMPLE = [
  # scientific name           call count
  ['Hirundo rustica',         4],
  ['Erithacus rubecula',      12],
  ['Sturnus vulgaris',        6],
  ['Turdus merula',           9],
  ['Corvus corax',            2],
  ['Fringilla coelebs',       5],
  ['Carduelis carduelis',     3],
  ['Saxicola rubicola',       2],
  ['Anthus pratensis',        7],
  ['Troglodytes troglodytes', 8],
  ['Pyrrhocorax pyrrhocorax', 1],
  ['Numenius arquata',        1],
  ['Cyanistes caeruleus',     5],
  ['Alauda arvensis',         3]
].freeze

Detection.where(Date: Date.current).delete_all

base = Time.zone.now
SAMPLE.each_with_index do |(sci, count), species_index|
  com = BirdName.lookup(sci).en
  count.times do |call_index|
    heard = base - (((species_index * 11) + call_index) * 60)
    Detection.create!(
      Date:       Date.current,
      Time:       heard,
      Sci_Name:   sci,
      Com_Name:   com,
      Confidence: 0.7 + ((call_index % 3) * 0.08),
      Week:       Date.current.cweek
    )
  end
end

# rubocop:disable Rails/Output -- seed feedback to the console is intentional
puts "Seeded #{Detection.where(Date: Date.current).count} detections " \
     "across #{SAMPLE.size} species for #{Date.current}."
# rubocop:enable Rails/Output
