namespace :birdlife do
  desc 'Regenerate the home page "today" summary (Nova Lite via Bedrock) into storage/today_summary.json'
  task summary_refresh: :environment do
    result = TodaySummary.refresh
    puts "summary refreshed (#{result[:source]}):"
    result[:bullets].each { |bullet| puts "  #{bullet}" }
  end
end
