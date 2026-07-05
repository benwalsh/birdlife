import { useEffect } from 'react'
import { useSpecies } from '../api'
import { useLang } from '../lang'
import { FollowButton } from './FollowButton'
import { AudioBar } from './AudioBar'
import { ago, stamp } from '../time'
import type { Bilingual, EnrichmentBlock } from '../types'

// One fact/folklore block, verbatim from the enrichment bundle, with its citations
// as quiet host links — the card renders what Ruby sourced, it never re-derives.
function Lore({ kind, block, tone }: { kind: string; block: EnrichmentBlock; tone: string }) {
  return (
    <p className={`modal-lore-item ${tone}`}>
      <span className="modal-lore-k">{kind}</span>
      <span className="modal-lore-text">{block.text}</span>
      {block.sources.length > 0 && (
        <span className="modal-lore-src">
          {block.sources.map((s, i) => (
            <a key={i} href={s.url} target="_blank" rel="noopener noreferrer">
              {s.host ?? 'source'}
            </a>
          ))}
        </span>
      )}
    </p>
  )
}

// The species-detail overlay. Reuses the .modal-* design-system classes (loaded
// via avian/application.css); data from /api/species/:sci. Header carries the
// follow checkbox (left) and the EN|GA toggle + close (right); the panel closes
// with the station's own signature.
export function SpeciesModal({
  sci,
  onClose,
  place,
}: {
  sci: string
  onClose: () => void
  place: Bilingual | null
}) {
  const { data } = useSpecies(sci)
  const { lang, setLang, t } = useLang()

  useEffect(() => {
    const onEsc = (e: KeyboardEvent) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onEsc)
    document.body.classList.add('modal-open')
    return () => {
      document.removeEventListener('keydown', onEsc)
      document.body.classList.remove('modal-open')
    }
  }, [onClose])

  const name = data ? (lang === 'ga' && data.ga ? data.ga : data.en) : ''
  // The other language, shown as the subtitle (Irish under English, or vice versa).
  const subtitle = data ? (lang === 'ga' ? data.en : data.ga) : null
  const desc = data ? (lang === 'ga' ? data.description_ga || data.description : data.description) : null
  const cons = data?.conservation
  const enr = data?.enrichment

  return (
    <div id="detail-modal" className="is-open">
      <div className="modal-backdrop" onClick={onClose} />
      <article className="modal-card">
        {data && (
          <>
            <div className="modal-head">
              <FollowButton sci={data.sci} variant="full" />
              <div className="modal-head-right">
                <div className="ed-lang" role="group" aria-label="Language">
                  <button className={`ed-lang-opt${lang === 'en' ? ' is-on' : ''}`} onClick={() => setLang('en')}>EN</button>
                  <button className={`ed-lang-opt${lang === 'ga' ? ' is-on' : ''}`} onClick={() => setLang('ga')}>GA</button>
                </div>
                <button className="modal-close" aria-label="close" onClick={onClose}>×</button>
              </div>
            </div>

            <div className="modal-grid">
              <div className="modal-img">
                {data.illustrations.map((img) => (
                  <img key={img.label} src={img.url} alt={`${data.en} (${img.label})`} loading="eager" />
                ))}
              </div>
              <div className="modal-info">
                {cons?.status && (
                  <div className={`cons-line ${cons.status}`}>
                    <span className={`cons-dot ${cons.status}`} />
                    <span className="cons-name">{cons.name} list</span>
                    <span className="cons-note">{cons.note}</span>
                  </div>
                )}
                <h2>{name}</h2>
                {subtitle && subtitle !== name && <p className="common">{subtitle}</p>}
                <p className="sci">{data.sci}</p>
                <div className="modal-stats">
                  <div><span className="n">{data.all_time.toLocaleString()}</span><span className="lbl">{t('all time', 'riamh')}</span></div>
                  <div><span className="n">{data.today.toLocaleString()}</span><span className="lbl">{t('today', 'inniu')}</span></div>
                  <div><span className="n">{ago(data.first_seen)}</span><span className="lbl">{t('first heard', 'chéad chloiste')}</span></div>
                </div>
                {desc && <p className="desc">{desc}</p>}
                {enr && (enr.fact || enr.folklore) && (
                  <div className="modal-lore">
                    {enr.fact && <Lore kind={t('Fact', 'Fíric')} block={enr.fact} tone="is-fact" />}
                    {enr.folklore && <Lore kind={t('Folklore', 'Béaloideas')} block={enr.folklore} tone="is-folk" />}
                  </div>
                )}
                {data.song && (
                  <div className="modal-audio">
                    <span className="modal-audio-label">{t('Listen to the call', 'Éist leis an nglao')}</span>
                    <AudioBar src={data.song} />
                  </div>
                )}
              </div>
            </div>

            <div className="modal-recordings">
              <div className="rec-head">
                <h3>{t('Detections', 'Aimsithe')}</h3>
                <span className="rec-count">{t('most recent', 'is déanaí')} {data.recent.length}</span>
              </div>
              <ol>
                {data.recent.map((r, i) => (
                  <li key={i}>
                    <span className="rec-when">{ago(r.at)}<small>{stamp(r.at)}</small></span>
                    <span className="rec-conf">{Math.round(r.confidence * 100)}%</span>
                  </li>
                ))}
              </ol>
            </div>

            <footer className="modal-foot">
              <span className="modal-foot-mark">Éist</span>
              <span>{t('Listening station', 'Stáisiún éisteachta')}</span>
              {place && <span>{lang === 'ga' ? place.ga : place.en}</span>}
            </footer>
          </>
        )}
      </article>
    </div>
  )
}
