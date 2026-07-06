import { useLang } from '../lang'
import type { Today } from '../types'

// The home page's TODAY block — the daily voice (bullets). The sparkline and the
// almanac row live above this (see TodaySpark, AlmanacRow). Everything is pre-shaped
// in Ruby; this view just iterates and prints.
export function TodayCard({ today }: { today: Today }) {
  const { t, lang } = useLang()
  const pick = (item: { en: string; ga: string }) => (lang === 'ga' ? item.ga : item.en)
  // The summary is bilingual { en, ga } — show the current language's bullets.
  const bullets = lang === 'ga' ? today?.summary?.ga : today?.summary?.en
  if (!bullets?.length) return null

  return (
    <section className="today-card">
      <header className="today-head">
        <span className="today-word">{t('Today', 'Inniu')}</span>
        <span className="today-date">{pick(today.date_label)}</span>
      </header>
      <hr className="today-rule" />

      <ul className="today-summary">
        {bullets.map((html, i) => (
          <li key={i} dangerouslySetInnerHTML={{ __html: html }} />
        ))}
      </ul>
    </section>
  )
}
