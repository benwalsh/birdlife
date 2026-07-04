# Logged-in users manage their own alert subscriptions ("email me if you hear a
# Corncrake"). Server-rendered + session-authed with Rails CSRF on the forms — the
# public JSON API stays cookie-free; this is the one authenticated write surface.
class SubscriptionsController < ApplicationController
  before_action :require_login, except: :unsubscribe

  def index
    @subscriptions = current_user.subscriptions.active.order(:alert_type, :sci_name)
    @species = species_options
  end

  def create
    sub = current_user.subscriptions.find_or_initialize_by(subscription_params)
    sub.update(active: true) # reactivates a previously-unsubscribed row, or creates
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

  def require_login
    redirect_to root_path unless logged_in?
  end

  def subscription_params
    params.expect(subscription: %i[alert_type sci_name])
  end

  # The 206 Irish (BoCCI) species, bilingual, sorted by English name — a sane
  # picker rather than all ~6000 BirdNET species.
  def species_options
    Conservation.species.map { |sci| [sci, BirdName.lookup(sci)] }.
      sort_by { |_sci, name| name.en }
  end
end
