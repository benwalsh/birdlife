import { useState } from 'react'
import { useDirectory } from '../api'
import { useLang } from '../lang'
import type { Sort, Scope } from '../types'

// The species directory (Eolaí) — the illustrated guide, in the same editorial
// broadsheet idiom as the rest of the site: no cards, no pills. Plain mono toggles,
// illustrations on paper, EB Garamond names + Irish italic, IBM Plex Mono counts.
const SORTS: { id: Sort; en: string; ga: string }[] = [
  { id: 'count', en: 'most heard', ga: 'is mó' },
  { id: 'recent', en: 'most recent', ga: 'is déanaí' },
  { id: 'alpha', en: 'a → z', ga: 'a → z' },
]
const SCOPES: { id: Scope; en: string; ga: string }[] = [
  { id: 'heard', en: 'heard', ga: 'cloiste' },
  { id: 'all', en: 'all species', ga: 'gach speiceas' },
]

export function DirectoryTab({ onSelect }: { onSelect: (sci: string) => void }) {
  const [sort, setSort] = useState<Sort>('count')
  const [scope, setScope] = useState<Scope>('heard')
  const { data, isLoading } = useDirectory(sort, scope)
  const { lang, t } = useLang()

  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? en : ga)

  return (
    <section className="dir">
      <div className="dir-controls">
        <div className="dir-group" role="tablist" aria-label="which birds">
          {SCOPES.map((s) => (
            <button key={s.id} className={`dir-opt${scope === s.id ? ' is-on' : ''}`}
                    aria-current={scope === s.id ? 'true' : undefined} onClick={() => setScope(s.id)}>
              {lang === 'ga' ? s.ga : s.en}
            </button>
          ))}
        </div>
        <div className="dir-group" role="tablist" aria-label="sort">
          {SORTS.map((s) => (
            <button key={s.id} className={`dir-opt${sort === s.id ? ' is-on' : ''}`}
                    aria-current={sort === s.id ? 'true' : undefined} onClick={() => setSort(s.id)}>
              {lang === 'ga' ? s.ga : s.en}
            </button>
          ))}
        </div>
      </div>

      {isLoading || !data ? (
        <p className="dir-loading">…</p>
      ) : (
        <div className="dir-grid">
          {data.species.map((e) => {
            const seen = e.count > 0
            return (
              <button key={e.sci} className={`dir-item${seen ? '' : ' unseen'}`} onClick={() => onSelect(e.sci)}>
                <span className="dir-plate">{e.image && <img src={e.image} alt={e.en} loading="lazy" />}</span>
                <span className="dir-name">
                  {primary(e.en, e.ga)}
                  {gloss(e.en, e.ga) && <em className="dir-gloss">{gloss(e.en, e.ga)}</em>}
                </span>
                <span className="dir-stat">
                  {seen
                    ? <><span className="dir-count">{e.count.toLocaleString()}</span> {t('heard', 'cloiste')}</>
                    : t('not yet heard', 'gan chloisteáil fós')}
                  {e.conservation && <span className={`dir-dot ${e.conservation}`} />}
                </span>
              </button>
            )
          })}
        </div>
      )}
    </section>
  )
}
