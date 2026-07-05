namespace :birdlife do
  desc "Stage 1: source enrichment bundles for a date (DATE=YYYY-MM-DD, SCI='Genus species' to force one)"
  task enrich: :environment do
    date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.current
    only = ENV['SCI'].present? ? { sci_name: ENV['SCI'] } : nil

    puts "Stage 1 — sourcing enrichment for #{date}#{" (forced: #{only[:sci_name]})" if only}"
    puts "  model: #{Bedrock.enrich_model_id}   bedrock disabled?: #{Bedrock.disabled?}"
    bundles = Enrichment::Builder.run(date: date, only: only)
    if bundles.empty?
      puts '  no bundles produced (no notable species, or the model/creds are unavailable).'
    else
      bundles.each { |b| print_bundle(b) }
    end
  end

  desc 'Run the full email-construction flow for one reader and render a preview (USER=id DATE=YYYY-MM-DD)'
  task email_flow: :environment do
    user = ENV['USER'].present? ? User.find(ENV['USER']) : User.first
    date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.yesterday
    abort 'no user found (pass USER=<id>)' unless user

    rule "1. TODAY'S DATA — #{date}"
    facts = DailyFacts.for(date: date)
    digest = DigestFacts.for(user: user, date: date)
    puts "  #{facts[:species_today]} species, #{facts[:detections_today]} detections."
    notable = EnrichmentGate.species_for(facts)
    puts "  notable birds (clear the enrichment bar): #{notable.pluck(:common_name).presence&.join(', ') || 'none'}"

    rule '2. STAGE 1 (Claude) — the interesting bits, sourced'
    puts "  model: #{Bedrock.enrich_model_id}   bedrock disabled?: #{Bedrock.disabled?}"
    # Source the day's notable birds AND the reader's own followed birds heard today,
    # so their report is actually about their birds. Reuse any bundle already sourced.
    wanted = (notable.pluck(:sci_name) + digest.follows.pluck(:sci)).uniq
    wanted.each do |sci|
      next if EnrichmentBundle.for_date(date).find { |b| b.sci_name == sci }&.block_objects&.any?

      puts "  sourcing #{sci}…"
      Enrichment::Builder.build_one(date: date, sci_name: sci)
    end
    bundles = EnrichmentBundle.for_date(date).select { |b| b.block_objects.any? }
    if bundles.empty?
      puts '  no enrichment available — the email will use the plain summary.'
      if (err = Enrichment::Builder.last_error)
        puts "  reason: #{err.class} — #{err.message.to_s.lines.first&.strip}"
        if err.message.to_s.match?(/use case|not been submitted|AccessDenied|ResourceNotFound/i)
          puts '  → the Bedrock Anthropic "use case details" form is not submitted for this'
          puts '    account. Fill it in the AWS console (Bedrock → Model access), wait ~15 min,'
          puts '    then re-run. Claude is the sourcing model; do not swap in another.'
        end
      end
    else
      bundles.each { |b| print_bundle(b) }
    end

    rule "3. THE READER — #{user.email}"
    puts "  follows heard: #{digest.follows.map { |f| "#{f[:en]} ×#{f[:count]}" }.presence&.join(', ') || 'none'}"
    puts "  standing-rule arrivals: #{digest.alerts.pluck(:en).presence&.join(', ') || 'none'}"
    puts "  daily letter: #{digest.roundup ? 'yes' : 'no'}"

    rule '4. STAGE 2 (Nova) — the note, assembled for this reader'
    note = Enrichment::Assembler.for(user: user, date: date)
    source = 'enrichment-assembled (Nova over the cited blocks)'
    if note.nil?
      note = DigestSummary.for(digest)
      source = note ? 'plain summary (Nova, no enrichment used)' : 'mechanical list (no model)'
    end
    puts "  source: #{source}"
    Array(note).each { |para| puts "  #{para}" }

    rule '5. RENDERED EMAIL'
    html = Notifier.send(:digest_html, digest, date, note)
    text = Notifier.send(:digest_text, digest, date, note)
    out = Rails.root.join('tmp/digest_preview.html')
    File.write(out, html)
    puts text.lines.map { |l| "  #{l}" }.join
    puts "\n  HTML preview written to #{out}"
  end
end

def print_bundle(bundle)
  puts "  • #{bundle.common_name} (#{bundle.sci_name})"
  bundle.block_objects.each do |block|
    hosts = block.sources.map { |s| s[:host] }.join(', ')
    puts "      [#{block.type}#{', gated' if block.gated?}] #{block.text}"
    puts "        ← #{hosts}" if hosts.present?
  end
end

def rule(title)
  puts "\n#{'─' * 4} #{title} #{'─' * [0, 64 - title.length].max}"
end
