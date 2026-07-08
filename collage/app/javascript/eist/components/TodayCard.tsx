import { useLang } from '../lang'
import type { Today } from '../types'

// Friendly names for the citation hosts; anything unlisted shows its bare domain.
const HOST_LABEL: Record<string, string> = {
  'duchas.ie': 'dúchas.ie',
  'www.duchas.ie': 'dúchas.ie',
  'celt.ucc.ie': 'CELT',
  'en.wikipedia.org': 'Wikipedia',
  'ga.wikipedia.org': 'Vicipéid',
  'birdwatchireland.ie': 'BirdWatch Ireland',
  'www.birdwatchireland.ie': 'BirdWatch Ireland',
  'irishbirding.com': 'Irish Birding',
  'www.irishbirding.com': 'Irish Birding',
  'irbc.ie': 'Irish Rare Birds Committee',
  'iwt.ie': 'Irish Wildlife Trust',
  'biodiversityireland.ie': 'Biodiversity Ireland',
  'irishheritagenews.ie': 'Irish Heritage News',
}
const label = (host: string) => HOST_LABEL[host] ?? host.replace(/^www\./, '')

// One link per distinct source (collapsing www/non-www to one label), keeping the first URL.
function distinctSources(sources: { host: string; url: string }[]) {
  const seen = new Map<string, string>()
  for (const s of sources) if (!seen.has(label(s.host))) seen.set(label(s.host), s.url)
  return [...seen].map(([name, url]) => ({ name, url }))
}

// The home page's TODAY block — the daily voice (bullets), then the sources the day's bird
// facts & folklore were drawn from. Everything is pre-shaped in Ruby; this view iterates.
export function TodayCard({ today }: { today: Today }) {
  const { t, lang } = useLang()
  const pick = (item: { en: string; ga: string }) => (lang === 'ga' ? item.ga : item.en)
  // The summary is bilingual { en, ga } — show the current language's bullets. Only the
  // warm, narrated version earns a place; the plain deterministic template is never shown
  // (better no "today" note than a bare "N species, most heard …" line).
  const bullets = lang === 'ga' ? today?.summary?.ga : today?.summary?.en
  if (!bullets?.length || today.source === 'template') return null

  const sources = distinctSources(today.sources ?? [])

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

      {sources.length > 0 && (
        <p className="today-sources">
          <span className="today-sources-label">{t('Facts & folklore', 'Fíricí is béaloideas')}</span>
          {sources.map((s) => (
            <a key={s.name} href={s.url} target="_blank" rel="noopener noreferrer">{s.name}</a>
          ))}
        </p>
      )}
    </section>
  )
}
