# A user's standing alert request. 'species' subscriptions carry a sci_name
# ("email me if you hear a Corncrake"); 'rarity' / 'first_ever' are species-less
# standing rules. Email goes to the user's OAuth address.
class Subscription < ApplicationRecord
  ALERT_TYPES = %w[species rarity first_ever seasonal].freeze
  delegate :email, to: :user
  belongs_to :user
  has_secure_token # :token — unguessable handle for unsubscribe links

  validates :alert_type, inclusion: { in: ALERT_TYPES }
  validates :sci_name, presence: true, if: -> { alert_type == 'species' }

  scope :active, -> { where(active: true) }
  scope :for_species, ->(sci) { active.where(alert_type: 'species', sci_name: sci) }
  scope :of_type, ->(type) { active.where(alert_type: type) }
end
