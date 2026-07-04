# A noteworthy occurrence worth emailing about, recorded once per type+species+day
# (unique index). notified_at is nil until the alert email is sent; a failed send
# leaves it nil so the next ingest tick retries.
class Event < ApplicationRecord
  validates :event_type, :sci_name, :occurred_on, presence: true

  scope :pending, -> { where(notified_at: nil) }

  def mark_notified!
    update!(notified_at: Time.current)
  end
end
