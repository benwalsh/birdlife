class StatsController < ApplicationController
  def show
    @top_species = Detection.tally_within(current_window).first(12)
    @by_period = Detection.by_period
    @first_seen = Detection.first_detections
  end
end
