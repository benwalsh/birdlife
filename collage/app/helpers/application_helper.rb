module ApplicationHelper
  # Compact relative time like the parent's panel: "now", "8h ago", "36d ago".
  def heard_ago(time)
    return '—' unless time

    secs = Time.current - time
    case secs
    when 0...60 then 'now'
    when 60...3600 then "#{(secs / 60).floor}m ago"
    when 3600...86_400 then "#{(secs / 3600).floor}h ago"
    else "#{(secs / 86_400).floor}d ago"
    end
  end

  # URL for a species' illustration, or nil if we don't ship one yet.
  def bird_illustration(sci)
    slug = sci.downcase.tr(' ', '-')
    file = Rails.public_path.join('birds', "#{slug}.png")
    # ?v=mtime busts the browser cache when a bird is regenerated.
    file.exist? ? "/birds/#{slug}.png?v=#{file.mtime.to_i}" : nil
  end

  # Both illustration poses for the modal — perched and (when we have it) in
  # flight — as [label, url] pairs, skipping any we don't ship. The collage only
  # shows one pose per bird; the card is where you see both.
  def bird_illustrations(sci)
    slug = sci.downcase.tr(' ', '-')
    { 'perched' => "#{slug}.png", 'in flight' => "#{slug}-2.png" }.filter_map do |label, name|
      file = Rails.public_path.join('birds', name)
      [label, "/birds/#{name}?v=#{file.mtime.to_i}"] if file.exist?
    end
  end
end
