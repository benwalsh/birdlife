class SpeciesController < ApplicationController
  def show
    @sci = params[:sci]
    @name = BirdName.lookup(@sci)
    scope = Detection.where(Sci_Name: @sci)

    @all_time = scope.count
    @today = scope.merge(Detection.today).count
    @first_seen = parse_time(scope.minimum(Arel.sql(Detection::WHEN_SQL)))
    @recent = scope.order(Arel.sql("#{Detection::WHEN_SQL} DESC")).limit(24)
    @description = SpeciesInfo.english_for(@sci, @name.en)
    @description_ga = SpeciesInfo.irish_for(@sci, @name.ga)

    render layout: false
  end

  private

  def parse_time(string)
    Time.zone.parse(string) if string.present?
  rescue ArgumentError
    nil
  end
end
