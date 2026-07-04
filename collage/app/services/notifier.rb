# Sends one alert email via SES *templated* email — the template (subject + HTML +
# text with {{placeholders}}) lives in SES, so there's no ActionMailer or view
# rendering here; we just pass a data blob. Images are plain URLs to the
# CloudFront-hosted illustrations, not attachments.
#
# Disabled unless ALERTS_FROM is set, so dev, test, and the Pi never try to send.
# Returns true on success (or when disabled) and false on failure — the caller
# leaves the event unsent on false so the next ingest tick retries.
class Notifier
  TEMPLATE = 'eist-alert'.freeze

  # Why this bird is worth an email — one line per alert kind, in the house voice.
  # The SES template prints {{reason}}; {{headline}} is the subject line.
  REASON = {
    'rarity'     => 'A locally scarce bird — heard on only a handful of days.',
    'seasonal'   => 'Back for the season, after a spell away.',
    'first_ever' => 'The first time the station has ever heard this one.',
    'species'    => 'One of the birds you follow.'
  }.freeze
  HEADLINE = {
    'rarity'     => ->(name) { "A local rarity: #{name}" },
    'seasonal'   => ->(name) { "#{name} — back for the season" },
    'first_ever' => ->(name) { "First ever at the cottage: #{name}" },
    'species'    => ->(name) { "#{name} — a bird you follow" }
  }.freeze

  class << self
    def deliver(event:, subscription:)
      return true unless enabled?

      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [subscription.email] },
        content:            { template: { template_name: TEMPLATE,
                                          template_data: data_for(event, subscription).to_json } }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[alerts] send failed for #{subscription.email}: #{e.class} #{e.message}")
      false
    end

    # One digest email — a DigestFacts object, narrated by DigestSummary (with the
    # mechanical list as fallback). SES *simple* content, not a template, since it's
    # variable and part LLM-written. Same fail-soft contract as deliver.
    def deliver_digest(user:, date:, facts:)
      return true unless enabled?

      note = DigestSummary.for(facts) # LLM note, or nil → the list stands on its own
      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [user.email] },
        content:            { simple: {
          subject: { data: "Your cottage birds — #{I18n.l(date, format: :long)}" },
          body:    { html: { data: digest_html(facts, date, note) }, text: { data: digest_text(facts, date, note) } }
        } }
      )
      true
    rescue StandardError => e
      Rails.logger.warn("[digest] send failed for #{user.email}: #{e.class} #{e.message}")
      false
    end

    def enabled?
      ENV['ALERTS_FROM'].present?
    end

    private

    def client
      @client ||= Aws::SESV2::Client.new
    end

    # Display rows: the followed birds heard (with counts), then the flagged arrivals.
    def digest_rows(facts)
      follows = facts.follows.map { |f| { en: f[:en], ga: f[:ga], note: "heard #{f[:count]}×" } }
      alerts  = facts.alerts.map { |a| { en: a[:en], ga: a[:ga], note: REASON.fetch(a[:kind], '') } }
      follows + alerts
    end

    def digest_html(facts, date, note)
      prose = Array(note).map do |para|
        %(<p style="font-size:16px;line-height:1.55;margin:0 0 12px;">#{h(para)}</p>)
      end.join
      rows = digest_rows(facts).map do |row|
        <<-ROW
          <tr><td style="padding:11px 0;border-bottom:1px solid #e4e4e7;">
            <span style="font-size:17px;color:#17171a;">#{h(row[:en])}</span>
            <span style="font-size:14px;color:#8b8b91;font-style:italic;">&nbsp;#{h(row[:ga])}</span>
            <span style="font-size:13px;color:#8b8b91;float:right;">#{h(row[:note])}</span>
          </td></tr>
        ROW
      end.join
      day = if facts.roundup
              "#{facts.roundup[:species_today]} species, #{facts.roundup[:detections_today]} detections"
            end
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">Éist · #{h(I18n.l(date, format: :long))}</div>
            <div style="font-size:24px;margin:6px 0 14px;">The day's birds at Culfin</div>
            #{prose}
            #{%(<table style="width:100%;border-collapse:collapse;margin-top:6px;">#{rows}</table>) unless rows.empty?}
            #{%(<div style="font-size:13px;color:#8b8b91;margin-top:14px;">#{h(day)} logged today.</div>) if day}
            <a href="#{site_url}" style="display:inline-block;margin-top:20px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">See the collage</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage how you're told at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>.</div>
          </div>
        </div>
      HTML
    end

    def digest_text(facts, date, note)
      prose = Array(note).join("\n\n")
      rows = digest_rows(facts).map { |row| "- #{row[:en]} (#{row[:ga]}) — #{row[:note]}" }.join("\n")
      body = [prose.presence, rows.presence].compact.join("\n\n")
      "The day's birds at Culfin — #{I18n.l(date, format: :long)}\n\n#{body}\n\n" \
        "See the collage: #{site_url}\nManage: #{site_url}/account"
    end

    def h(text)
      ERB::Util.html_escape(text)
    end

    def data_for(event, subscription)
      name = BirdName.lookup(event.sci_name)
      slug = event.sci_name.downcase.tr(' ', '-')
      kind = event.event_type
      {
        kind:            kind,
        reason:          REASON.fetch(kind, 'Heard at the cottage.'),
        headline:        (HEADLINE[kind] || ->(n) { "#{n} heard at Culfin" }).call(name.en),
        en:              name.en,
        ga:              name.ga,
        sci:             event.sci_name,
        date:            I18n.l(event.occurred_on, format: :long),
        image_url:       "#{site_url}/birds/#{slug}.png",
        site_url:        site_url,
        unsubscribe_url: "#{site_url}/subscriptions/#{subscription.token}/unsubscribe"
      }
    end

    def site_url
      ENV.fetch('SITE_URL', 'https://culfinbirds.net')
    end
  end
end
