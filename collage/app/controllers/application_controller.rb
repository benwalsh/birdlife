class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # The time-range window shared by every view (the top picker). Hours; a huge
  # value means "all time".
  WINDOWS = [['1H', 1], ['12H', 12], ['24H', 24], ['7D', 168], ['ALL', 1_000_000]].freeze

  private

  def current_window
    valid = WINDOWS.map { |_label, hours| hours }
    valid.include?(params[:h]&.to_i) ? params[:h].to_i : 24
  end
  helper_method :current_window

  def window_label
    WINDOWS.find { |_label, hours| hours == current_window }&.first
  end
  helper_method :window_label

  # Human phrase for the caption's windowed count ("… 12 calls today").
  def window_phrase
    { 1 => 'in the last hour', 12 => 'in the last 12 hours', 24 => 'today',
      168 => 'this week', 1_000_000 => 'all-time' }.fetch(current_window, 'recently')
  end
  helper_method :window_phrase
end
