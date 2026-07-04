import { useLang } from '../lang'
import type { Today } from '../types'

// The home page's TODAY block — the daily voice (bullets) + the ambient footer.
// The sparkline lives above this, between the collage and here (see TodaySpark).
// Everything is pre-shaped in Ruby; this view just iterates and prints.
export function TodayCard({ today }: { today: Today }) {
  const { t, lang } = useLang()
  if (!today?.summary?.length) return null

  const pick = (item: { en: string; ga: string }) => (lang === 'ga' ? item.ga : item.en)

  return (
    <section className="today-card">
      <header className="today-head">
        <span className="today-word">{t('Today', 'Inniu')}</span>
        <span className="today-date">{pick(today.date_label)}</span>
      </header>
      <hr className="today-rule" />

      <ul className="today-summary">
        {today.summary.map((html, i) => (
          <li key={i} dangerouslySetInnerHTML={{ __html: html }} />
        ))}
      </ul>

      <hr className="today-rule" />
      <ul className="today-footer">
        {today.footer.map((f, i) => (
          <li key={i}>
            <i className={`ti ${f.icon}`} aria-hidden="true" /> {pick(f)}
          </li>
        ))}
      </ul>
    </section>
  )
}
