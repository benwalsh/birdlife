import type { SparkPaths } from '../types'

// The single live gesture on the paper. The path maths is done in Ruby (see
// Sparkline service); this only prints the two path strings. A very low-opacity
// vertical gradient fills under a thin green stroke — no axes, no dots.
export function Sparkline({ paths }: { paths: SparkPaths }) {
  const { path, fill, ghost, w, h } = paths
  return (
    <svg className="today-spark-svg" viewBox={`0 0 ${w} ${h}`} width={w} height={h}
         preserveAspectRatio="none" aria-hidden="true">
      <defs>
        <linearGradient id="spark-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--green)" stopOpacity="0.18" />
          <stop offset="1" stopColor="var(--green)" stopOpacity="0" />
        </linearGradient>
      </defs>
      <path d={fill} fill="url(#spark-fill)" stroke="none" />
      {/* A blind spot — the mic was down — as a faint dotted baseline: unknown, not zero. */}
      {ghost && <path d={ghost} fill="none" className="today-spark-ghost" />}
      <path d={path} fill="none" className="today-spark-line" />
    </svg>
  )
}
