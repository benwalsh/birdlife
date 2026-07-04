# Alert emails via SES (eu-west-1, same region as the app). The domain is verified
# by Easy DKIM; a custom MAIL FROM gives SPF alignment; the template lives here so
# the Rails Notifier just passes data. NB: SES starts in the SANDBOX — it can only
# email *verified* addresses until you request production access (a support ticket,
# a day or two of lead time). See the README.

resource "aws_sesv2_email_identity" "main" {
  email_identity = var.domain_name # culfinbirds.net — Easy DKIM by default
}

# Publish the 3 Easy-DKIM CNAMEs so SES can verify + sign for the domain.
resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = aws_route53_zone.main.zone_id
  name    = "${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.main.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# Custom MAIL FROM (mail.culfinbirds.net) so SPF aligns with the From domain.
resource "aws_sesv2_email_identity_mail_from_attributes" "main" {
  email_identity         = aws_sesv2_email_identity.main.email_identity
  mail_from_domain       = "mail.${var.domain_name}"
  behavior_on_mx_failure = "USE_DEFAULT_VALUE"
}

resource "aws_route53_record" "ses_mail_from_mx" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type    = "MX"
  ttl     = 600
  records = ["10 feedback-smtp.${var.aws_region}.amazonses.com"]
}

resource "aws_route53_record" "ses_mail_from_spf" {
  zone_id = aws_route53_zone.main.zone_id
  name    = aws_sesv2_email_identity_mail_from_attributes.main.mail_from_domain
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}

# Minimal DMARC (monitor-only) so mailbox providers see a policy.
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 600
  records = ["v=DMARC1; p=none;"]
}

# The alert template the Notifier renders by name. Placeholders match Notifier's
# data blob: kind, en, ga, sci, date, image_url, site_url, unsubscribe_url. Email
# HTML must inline its colours (no CSS vars in mail) — kept on-palette with the site.
resource "aws_ses_template" "alert" {
  name    = "eist-alert"
  subject = "{{en}} heard at Culfin — {{date}}"

  html = <<-HTML
    <div style="margin:0;padding:24px;background:#f2f2f3;font-family:Georgia,'Times New Roman',serif;color:#17171a;">
      <div style="max-width:520px;margin:0 auto;background:#ffffff;border:1px solid #e4e4e7;border-radius:10px;overflow:hidden;">
        <img src="{{image_url}}" alt="{{en}}" width="520" style="display:block;width:100%;height:auto;background:#f2f2f3;">
        <div style="padding:24px 28px;">
          <div style="font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:#8b8b91;margin-bottom:10px;">Heard at Culfin</div>
          <div style="font-size:26px;line-height:1.15;">{{en}}</div>
          <div style="font-size:18px;color:#3d3d42;margin-top:2px;">{{ga}}</div>
          <div style="font-size:14px;font-style:italic;color:#8b8b91;margin-top:6px;">{{sci}}</div>
          <p style="font-size:15px;color:#3d3d42;line-height:1.55;margin:18px 0 22px;">
            A <strong>{{kind}}</strong> detection on {{date}}. The listening station at the cottage picked it up.
          </p>
          <a href="{{site_url}}" style="display:inline-block;background:#17171a;color:#ffffff;text-decoration:none;font-family:Helvetica,Arial,sans-serif;font-size:14px;padding:11px 20px;border-radius:6px;">See the collage</a>
        </div>
        <div style="padding:16px 28px;border-top:1px solid #e4e4e7;font-family:Helvetica,Arial,sans-serif;font-size:12px;color:#8b8b91;">
          You asked to hear about this. <a href="{{unsubscribe_url}}" style="color:#8b8b91;">Unsubscribe</a>.
        </div>
      </div>
    </div>
  HTML

  text = <<-TEXT
    {{en}} ({{ga}}) — {{sci}}
    A {{kind}} detection at Culfin on {{date}}.

    See the collage: {{site_url}}
    Unsubscribe: {{unsubscribe_url}}
  TEXT
}

# Let the ECS task send mail as this domain (SES v2 SendEmail authorises on the
# "From" identity). Attached to the module-created task role.
resource "aws_iam_role_policy" "task_ses" {
  name = "culfinbirds-task-ses"
  role = module.express_service.task_iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "SendAlertEmail"
      Effect   = "Allow"
      Action   = ["ses:SendEmail"]
      Resource = [aws_sesv2_email_identity.main.arn]
    }]
  })
}
