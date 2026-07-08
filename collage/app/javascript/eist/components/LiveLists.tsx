import { useLang } from '../lang'
import { ago, shortDate } from '../time'
import type { Tally, LifeEntry } from '../types'

// Live's reading body: two ruled columns below New & notable — Recently heard (the
// window's birds, freshest first, with time-ago) and First detections (newest additions
// to the life list, with the date). Present-tense counterpart to the collage: the collage
// is *which* birds, these are *when*. Reuses the editorial .ed-cols/.ed-row idiom.
export function LiveLists({
  recent,
  firstSeen,
  onSelect,
}: {
  recent: Tally[]
  firstSeen: LifeEntry[]
  onSelect: (sci: string) => void
}) {
  const { t, lang } = useLang()
  const primary = (en: string, ga: string | null) => (lang === 'ga' && ga ? ga : en)
  const gloss = (en: string, ga: string | null) => (lang === 'ga' ? (ga ? en : null) : ga)

  const name = (en: string, ga: string | null) => (
    <span className="ed-row-name">
      {primary(en, ga)}
      {gloss(en, ga) && <em className="ed-gloss">{gloss(en, ga)}</em>}
    </span>
  )

  if (!recent.length) return null

  return (
    <div className="ed-cols live-lists">
      <div className="ed-grp">
        <div className="ed-col-head">
          <h2>{t('Recently heard', 'Cloiste le déanaí')}</h2>
        </div>
        <ul className="ed-list">
          {recent.map((r) => (
            <li key={r.sci}>
              <button className="ed-row" onClick={() => onSelect(r.sci)}>
                {name(r.en, r.ga)}
                <span className="ed-row-meta">{ago(r.last_time, lang)}</span>
              </button>
            </li>
          ))}
        </ul>
      </div>

      {firstSeen.length > 0 && (
        <div className="ed-grp">
          <div className="ed-col-head">
            <h2>{t('First detections', 'Céadaimsithe')}</h2>
          </div>
          <ul className="ed-list">
            {firstSeen.map((e) => (
              <li key={e.sci}>
                <button className="ed-row" onClick={() => onSelect(e.sci)}>
                  {name(e.en, e.ga)}
                  <span className="ed-row-meta yr">{shortDate(e.first_seen, lang)}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
