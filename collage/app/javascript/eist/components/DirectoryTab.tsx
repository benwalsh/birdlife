import { useState } from 'react'
import { useDirectory } from '../api'
import { useLang } from '../lang'
import { ago } from '../time'
import { FollowButton } from './FollowButton'
import type { Sort, Scope, Conservation } from '../types'

// The species directory (Eolaí) — the illustrated guide. Each plate echoes the detail
// card: a follow mark, the conservation status above the name, the binomial, and the
// all-time / today / first-heard figures.
// BoCCI status → its display name + a tooltip gloss (matches the detail card's wording).
const CONS: Record<'red' | 'amber' | 'green', { name: string; note: string }> = {
  red: { name: 'Red', note: 'High conservation concern in Ireland' },
  amber: { name: 'Amber', note: 'Moderate conservation concern in Ireland' },
  green: { name: 'Green', note: 'Least conservation concern in Ireland' },
}
const consOf = (c: Conservation) => (c ? CONS[c] : null)

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
            const c = consOf(e.conservation)
            return (
              <div key={e.sci} className="dir-cell">
                <FollowButton sci={e.sci} variant="card" />
                <button className={`dir-item${seen ? '' : ' unseen'}`} onClick={() => onSelect(e.sci)}>
                  <span className="dir-plate">{e.image && <img src={e.image} alt={e.en} loading="lazy" />}</span>
                  {c && (
                    <span className="dir-pill" title={c.note}>
                      <span className={`dir-dot ${e.conservation}`} />{c.name}
                    </span>
                  )}
                  <span className="dir-name">{primary(e.en, e.ga)}</span>
                  {gloss(e.en, e.ga) && <em className="dir-gloss">{gloss(e.en, e.ga)}</em>}
                  <span className="dir-sci">{e.sci}</span>
                  {seen ? (
                    <span className="dir-stats">
                      <span><b>{e.count.toLocaleString()}</b> {t('all time', 'riamh')}</span>
                      <span><b>{e.today.toLocaleString()}</b> {t('today', 'inniu')}</span>
                      {e.first_seen && <span><b>{ago(e.first_seen)}</b> {t('first', 'céad')}</span>}
                    </span>
                  ) : (
                    <span className="dir-stats dir-unseen-note">{t('not yet heard', 'gan chloisteáil fós')}</span>
                  )}
                </button>
              </div>
            )
          })}
        </div>
      )}
    </section>
  )
}
