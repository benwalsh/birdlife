class AtlasController < ApplicationController
  SORTS = %w[count recent alpha].freeze

  def show
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : 'count'
    @scope = params[:scope] == 'all' ? 'all' : 'heard'
    @species = sorted(entries)
  end

  private

  # "heard" is the life list. "all" is the whole illustrated library, carrying
  # un-heard species as zero-count entries so they show greyed but browsable.
  def entries
    heard = Detection.life_list
    return heard unless @scope == 'all'

    seen = heard.index_by(&:sci_name)
    SpeciesCatalog.all_sci.map { |sci| seen[sci] || Detection::LifeEntry.new(sci, 0, nil, nil) }
  end

  # Un-heard birds always sort to the bottom (alphabetical among themselves),
  # except in a→z where they interleave by name — the natural browse order.
  def sorted(list)
    # entry.count is a LifeEntry's detection tally (an Integer), not a collection
    # size — so the CollectionQuerying "use any?" rewrite would be wrong here.
    seen, unseen = list.partition { |entry| entry.count.positive? } # rubocop:disable Style/CollectionQuerying
    case @sort
    when 'recent' then seen.sort_by(&:last_seen).reverse + alpha(unseen)
    when 'alpha'  then alpha(list)
    else seen.sort_by(&:count).reverse + alpha(unseen)
    end
  end

  def alpha(list)
    list.sort_by { |entry| (entry.name.ga || entry.name.en).downcase }
  end
end
