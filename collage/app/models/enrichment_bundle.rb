# A day's enrichment for one species — an array of typed, cited blocks (see
# Enrichment::Block), produced by Enrichment::Builder (Claude) and consumed by every
# subscriber's Enrichment::Assembler (Nova), so a single cuckoo lookup serves the whole
# subscriber base. Stored per (sci_name, date), but facts & folklore are durable: the
# MOST RECENT bundle for a species stands as current on any later day until a refresh
# is due (see Enrichment::Policy's importance-keyed backoff), so we never re-derive the
# same house-sparrow facts day after day.
class EnrichmentBundle < ApplicationRecord
  validates :sci_name, presence: true, uniqueness: { scope: :date }
  validates :date, presence: true

  scope :for_date, ->(date) { where(date: date) }

  class << self
    # The current (most recent) bundle for one species, or nil.
    def current(sci_name)
      where(sci_name: sci_name).order(date: :desc).first
    end

    # The current bundle for each of several species — the catalogue an assembler
    # reads, drawing each bird's latest enrichment whatever day it was sourced.
    def current_for(sci_names)
      where(sci_name: sci_names).order(date: :desc).uniq(&:sci_name)
    end
  end

  # The stored blocks as validated value objects. Invalid blocks are dropped — a
  # bundle only ever hands the assembler blocks that honour the contract.
  def block_objects
    Array(blocks).filter_map { |raw| Enrichment::Block.from(raw) }.select(&:valid?)
  end
end
