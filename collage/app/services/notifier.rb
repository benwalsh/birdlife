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

    def enabled?
      ENV['ALERTS_FROM'].present?
    end

    private

    def client
      @client ||= Aws::SESV2::Client.new
    end

    def data_for(event, subscription)
      name = BirdName.lookup(event.sci_name)
      slug = event.sci_name.downcase.tr(' ', '-')
      {
        kind:            event.event_type,
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
