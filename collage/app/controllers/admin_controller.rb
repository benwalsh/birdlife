# Admin-only surface, never linked from the public chrome. Gated by User#admin?
# (ADMIN_EMAILS, fail-closed). Session-authed like /account; kept out of the
# cookie-free /api and out of the CloudFront cache (see cdn.tf).
class AdminController < ApplicationController
  before_action :require_admin

  # The health panel — "is the box alive?" All figures come from AdminHealth.
  def index
    @health = AdminHealth.snapshot
  end

  private

  # Non-admins (signed in or not) are bounced home — the page isn't advertised.
  def require_admin
    redirect_to root_path unless current_user&.admin?
  end
end
