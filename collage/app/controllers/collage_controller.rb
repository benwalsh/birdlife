class CollageController < ApplicationController
  def show
    @collage = collage
  end

  # The bare 800x480 SVG, no chrome — what the Inky shooter screenshots.
  def panel
    @collage = collage
    render partial: 'panel', layout: false
  end

  private

  def collage
    CollagePresenter.new(Detection.tally_within(current_window))
  end
end
