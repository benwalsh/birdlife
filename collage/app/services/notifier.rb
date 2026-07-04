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

    # One digest email — the day's events, built inline (SES *simple* content, not a
    # template, since the list is variable-length). Same fail-soft contract as deliver.
    def deliver_digest(user:, date:, events:)
      return true unless enabled?

      client.send_email(
        from_email_address: ENV.fetch('ALERTS_FROM'),
        destination:        { to_addresses: [user.email] },
        content:            { simple: {
          subject: { data: "Your cottage birds — #{I18n.l(date, format: :long)}" },
          body:    { html: { data: digest_html(events, date) }, text: { data: digest_text(events, date) } }
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

    def digest_html(events, date)
      rows = events.map do |event|
        name = BirdName.lookup(event.sci_name)
        <<-ROW
          <tr><td style="padding:12px 0;border-bottom:1px solid #e4e4e7;">
            <div style="font-size:18px;color:#17171a;">#{h(name.en)}</div>
            <div style="font-size:14px;color:#8b8b91;font-style:italic;">#{h(name.ga)}</div>
            <div style="font-size:13px;color:#3d3d42;margin-top:3px;">#{h(REASON.fetch(event.event_type, ''))}</div>
          </td></tr>
        ROW
      end.join
      <<-HTML
        <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
          <div style="max-width:520px;margin:0 auto;background:#fff;border:1px solid #e4e4e7;border-radius:10px;padding:24px 28px;">
            <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;">Éist · #{h(I18n.l(date, format: :long))}</div>
            <div style="font-size:24px;margin:6px 0 2px;">The day's birds at Culfin</div>
            <table style="width:100%;border-collapse:collapse;margin-top:12px;">#{rows}</table>
            <a href="#{site_url}" style="display:inline-block;margin-top:22px;background:#17171a;color:#fff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">See the collage</a>
            <div style="margin-top:16px;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">Manage how you're told at <a href="#{site_url}/account" style="color:#8b8b91;">your account</a>.</div>
          </div>
        </div>
      HTML
    end

    def digest_text(events, date)
      lines = events.map do |event|
        name = BirdName.lookup(event.sci_name)
        "- #{name.en} (#{name.ga}) — #{REASON.fetch(event.event_type, '')}"
      end
      "The day's birds at Culfin — #{I18n.l(date, format: :long)}\n\n#{lines.join("\n")}\n\n" \
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
