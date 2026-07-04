# A day's enrichment for one notable species — an array of typed, cited blocks
# (see Enrichment::Block). Produced once by Enrichment::Builder and consumed by
# every subscriber's Email::Assembler, so a single cuckoo lookup on 15 April serves
# the whole subscriber base. Unique per (sci_name, date).
class EnrichmentBundle < ApplicationRecord
  validates :sci_name, presence: true, uniqueness: { scope: :date }
  validates :date, presence: true

  scope :for_date, ->(date) { where(date: date) }

  # The stored blocks as validated value objects. Invalid blocks are dropped — a
  # bundle only ever hands the assembler blocks that honour the contract.
  def block_objects
    Array(blocks).filter_map { |raw| Enrichment::Block.from(raw) }.select(&:valid?)
  end
end
