import { useLang } from '../lang'
import type { Today } from '../types'
import { Sparkline } from './Sparkline'

// The 24h activity sparkline as its own quiet band between the collage and the
// TODAY text — the single live gesture, with minimal chrome: just the total and
// four plain clock-time ticks.
export function TodaySpark({ today }: { today: Today }) {
  const { lang } = useLang()
  if (!today?.sparkline) return null

  const pick = (a: { en: string; ga: string }) => (lang === 'ga' ? a.ga : a.en)
  // Keep the extreme ticks inside the edges; centre the rest on their mark.
  const shift = (x: number) => (x <= 0 ? '0' : x >= 1 ? '-100%' : '-50%')

  return (
    <section className="today-spark">
      <div className="today-spark-head">
        <span className="today-spark-total">{today.total.toLocaleString()}</span>
      </div>
      <Sparkline paths={today.sparkline} />
      <div className="today-anchors">
        {today.anchors.map((a, i) => (
          <span key={i} style={{ left: `${a.x * 100}%`, transform: `translateX(${shift(a.x)})` }}>
            {pick(a)}
          </span>
        ))}
      </div>
    </section>
  )
}
