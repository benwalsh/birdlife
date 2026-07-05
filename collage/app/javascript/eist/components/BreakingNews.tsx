import { useLang } from '../lang'
import type { BreakingItem, BreakingKind } from '../types'

// The kind label, bilingual — the one flourish this calm page allows itself.
const KIND: Record<BreakingKind, { en: string; ga: string }> = {
  first_ever: { en: 'First ever', ga: 'Céaduair riamh' },
  rarity: { en: 'Rarity', ga: 'Annamh' },
  seasonal: { en: 'Seasonal return', ga: 'Filleadh séasúrach' },
}

// The breaking strip: recent rarities, first-evers and seasonal returns, sitting above
// the day's summary. The same fire-once events the immediate email alerts fire on. Each
// bird is a button to its card. Renders nothing when there's no news — no empty banner.
export function BreakingNews({ items, onSelect }: { items: BreakingItem[]; onSelect: (sci: string) => void }) {
  const { t, lang } = useLang()
  if (!items.length) return null

  return (
    <section className="breaking" aria-label={t('Breaking', 'Nuacht')}>
      <span className="breaking-tag">{t('Breaking', 'Nuacht')}</span>
      <ul className="breaking-list">
        {items.map((it, i) => (
          <li key={i}>
            <button type="button" className={`breaking-item ${it.kind}`} onClick={() => onSelect(it.sci)}>
              <span className="breaking-kind">{t(KIND[it.kind].en, KIND[it.kind].ga)}</span>
              <span className="breaking-name">{lang === 'ga' && it.ga ? it.ga : it.en}</span>
            </button>
          </li>
        ))}
      </ul>
    </section>
  )
}
