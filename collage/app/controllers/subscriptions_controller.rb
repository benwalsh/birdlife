# Logged-in users manage their own alert subscriptions and how they're delivered.
# Server-rendered + session-authed with Rails CSRF on the forms — the public JSON
# API stays cookie-free; this is the one authenticated write surface (with the
# favourites toggle).
class SubscriptionsController < ApplicationController
  before_action :require_login, except: :unsubscribe

  # The species-less standing rules, in display order.
  STANDING_RULES = { 'rarity'     => 'Rarities & vagrants',
                     'seasonal'   => 'Seasonal returns',
                     'first_ever' => 'First-ever species' }.freeze

  def index
    subs = current_user.subscriptions.active
    @follows = subs.where(alert_type: 'species').order(:sci_name)
    # type => current cadence ('off' when there's no active row for it).
    @rule_cadence = STANDING_RULES.keys.index_with do |type|
      subs.find_by(alert_type: type, sci_name: nil)&.cadence || 'off'
    end
    @follow_cadence = @follows.first&.cadence || 'immediate'
    @species = species_options
  end

  # Add a followed species from the picker; it inherits the user's current follow
  # cadence so a new follow behaves like the others.
  def create
    sub = current_user.subscriptions.find_or_initialize_by(subscription_params)
    sub.cadence = current_follow_cadence if sub.new_record?
    sub.update(active: true) # reactivates a previously-unsubscribed row, or creates
    redirect_to account_path
  end

  # Set how an alert type is delivered (immediate / digest / off). For the standing
  # rules 'off' removes the rule; for follows it bulk-sets every followed species
  # (they stay followed, just silent) so the account page can show one control.
  def cadence
    type = params[:alert_type]
    wanted = params[:cadence]
    return redirect_to(account_path) unless Subscription::CADENCES.include?(wanted)

    if type == 'species'
      # Bulk-set every follow in one statement; `wanted` is already validated above,
      # so the skipped per-row validations cost nothing.
      # rubocop:disable Rails/SkipsModelValidations
      current_user.subscriptions.where(alert_type: 'species').update_all(cadence: wanted)
      # rubocop:enable Rails/SkipsModelValidations
    elsif wanted == 'off'
      current_user.subscriptions.where(alert_type: type, sci_name: nil).destroy_all
    elsif STANDING_RULES.key?(type)
      current_user.subscriptions.find_or_initialize_by(alert_type: type, sci_name: nil).
        update!(active: true, cadence: wanted)
    end
    redirect_to account_path
  end

  def destroy
    current_user.subscriptions.find(params.expect(:id)).destroy
    redirect_to account_path
  end

  # One-click unsubscribe from an email link — token-authed, no login, idempotent.
  def unsubscribe
    @subscription = Subscription.find_by(token: params[:token])
    @subscription&.update(active: false)
  end

  private

  def subscription_params
    params.expect(subscription: %i[alert_type sci_name])
  end

  def current_follow_cadence
    current_user.subscriptions.find_by(alert_type: 'species')&.cadence || 'immediate'
  end

  # The 206 Irish (BoCCI) species, bilingual, sorted by English name — a sane
  # picker rather than all ~6000 BirdNET species.
  def species_options
    Conservation.species.map { |sci| [sci, BirdName.lookup(sci)] }.
      sort_by { |_sci, name| name.en }
  end
end
