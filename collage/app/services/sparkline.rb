# The one live gesture on the paper: the 24h activity sparkline, computed to SVG
# path strings in Ruby so the view does no path maths. It is NOT a literal plot of
# raw counts — sparse, spiky real data is gently smoothed into a believable curve
# (a moving-average pass, then a Catmull-Rom spline). A silent day rests as a flat
# gentle line, never a flat baseline with one vertical spike.
class Sparkline
  W = 700
  H = 88
  PAD = 6

  Paths = Data.define(:path, :fill, :ghost, :w, :h)

  class << self
    # counts: up to 24 hourly buckets (oldest first). Returns the stroke path (the
    # curve) and the fill path (same curve closed down to the baseline). coverage: an
    # optional boolean per bucket — false where the mic was down (missing data, not a
    # zero). Uncovered stretches are dropped from the curve and returned separately as a
    # `ghost` path (a faint dotted baseline the view draws), so a blind spot reads as
    # unknown, never as a confident flat zero.
    def paths(counts, coverage: nil, width: W, height: H, pad: PAD)
      counts = Array(counts).map(&:to_f)
      n = counts.length
      return flat(width, height, pad) if n < 2

      coverage = normalize_coverage(coverage, n)
      # No live curve to draw (silent-but-covered, or nothing known) → the resting line,
      # plus a ghost wherever the window is a genuine blind spot.
      return flat(width, height, pad, ghost: ghost_path(coverage, n, width, height, pad)) \
        if counts.sum.zero? || coverage.none?

      points = plot_points(smooth(counts), width, height, pad)
      # Each covered run becomes its own curve; runs of one point can't be splined.
      runs = covered_runs(coverage).map { |idxs| idxs.map { |i| points[i] } }.select { |run| run.length >= 2 }
      line = runs.map { |run| spline(run, width, height) }.join(' ')
      fill = runs.map { |run| fill_segment(run, width, height) }.join(' ')
      Paths.new(path: line, fill: fill, ghost: ghost_path(coverage, n, width, height, pad), w: width, h: height)
    end

    private

    # Fully covered when we have no coverage signal at all (nil, or no ticks in the
    # window) — we don't claim "missing" without evidence; that keeps the cloud mirror
    # and pre-heartbeat data drawing exactly as before.
    def normalize_coverage(coverage, count)
      return Array.new(count, true) if coverage.nil? || coverage.none?

      coverage.map { |c| !!c }
    end

    # Maximal runs of consecutive covered buckets, as arrays of indices.
    def covered_runs(coverage)
      runs = []
      coverage.each_index do |i|
        next unless coverage[i]

        if i.positive? && coverage[i - 1]
          runs.last << i
        else
          runs << [i]
        end
      end
      runs
    end

    # A faint dotted line along the baseline across every uncovered stretch — "the mic
    # was down here; activity unknown". nil when the window is fully covered.
    def ghost_path(coverage, count, width, height, pad)
      return nil if coverage.all?

      base = height - pad
      step = count > 1 ? (width - (2 * pad)) / (count - 1) : 0
      covered_runs(coverage.map(&:!)).filter_map do |idxs|
        x0 = pad + (idxs.first * step)
        x1 = pad + (idxs.last * step)
        "M #{r(x0)} #{r(base)} L #{r(x1)} #{r(base)}"
      end.join(' ').presence
    end

    # A gentle resting line low on the card — the honest picture of a quiet day.
    def flat(width, height, pad, ghost: nil)
      y = height - pad - ((height - (2 * pad)) * 0.12)
      path = "M #{pad} #{r(y)} L #{width - pad} #{r(y)}"
      fill = "#{path} L #{width - pad} #{height} L #{pad} #{height} Z"
      Paths.new(path: path, fill: fill, ghost: ghost, w: width, h: height)
    end

    # One covered run's curve, closed down to the baseline for the gradient fill.
    def fill_segment(points, width, height)
      "#{spline(points, width, height)} L #{r(points.last[0])} #{height} L #{r(points.first[0])} #{height} Z"
    end

    # Light 3-point moving average so a single loud hour becomes a soft rise, not a
    # spike. Applied before the spline, per the brief.
    def smooth(counts)
      counts.each_index.map do |i|
        lo = [i - 1, 0].max
        hi = [i + 1, counts.length - 1].min
        window = counts[lo..hi]
        window.sum / window.length
      end
    end

    # Map smoothed counts to points in the fixed viewBox space, y inverted so the
    # loudest hour sits highest.
    def plot_points(values, width, height, pad)
      max = [values.max, 1.0].max
      n = values.length
      values.each_index.map do |i|
        x = pad + ((i.to_f / (n - 1)) * (width - (2 * pad)))
        y = pad + ((1 - (values[i] / max)) * (height - (2 * pad)))
        [x, y]
      end
    end

    # A Catmull-Rom spline through the points, emitted as cubic béziers — a smooth,
    # continuous curve with no vertical spikes. Control points are clamped into the
    # viewBox so a sharp rise can't bulge the curve off the top of the card.
    def spline(points, width, height)
      d = ["M #{r(points[0][0])} #{r(points[0][1])}"]
      (0...(points.length - 1)).each do |i|
        p0 = i.positive? ? points[i - 1] : points[i]
        p1 = points[i]
        p2 = points[i + 1]
        p3 = points[i + 2] || p2
        c1x = clamp(p1[0] + ((p2[0] - p0[0]) / 6.0), 0, width)
        c1y = clamp(p1[1] + ((p2[1] - p0[1]) / 6.0), 0, height)
        c2x = clamp(p2[0] - ((p3[0] - p1[0]) / 6.0), 0, width)
        c2y = clamp(p2[1] - ((p3[1] - p1[1]) / 6.0), 0, height)
        d << "C #{r(c1x)} #{r(c1y)} #{r(c2x)} #{r(c2y)} #{r(p2[0])} #{r(p2[1])}"
      end
      d.join(' ')
    end

    def clamp(value, low, high)
      value.clamp(low, high)
    end

    def r(value)
      value.round(2)
    end
  end
end
