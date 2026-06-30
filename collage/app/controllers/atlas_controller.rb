class AtlasController < ApplicationController
  SORTS = %w[count recent alpha].freeze

  def show
    @sort = SORTS.include?(params[:sort]) ? params[:sort] : 'count'
    @species = sorted(Detection.life_list)
  end

  private

  def sorted(list)
    case @sort
    when 'recent' then list.sort_by(&:last_seen).reverse
    when 'alpha'  then list.sort_by { |entry| (entry.name.ga || entry.name.en).downcase }
    else list.sort_by(&:count).reverse
    end
  end
end
