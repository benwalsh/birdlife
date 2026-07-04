import { useEffect } from 'react'
import { useSpecies } from '../api'
import { useLang } from '../lang'
import { FollowButton } from './FollowButton'
import { ago, stamp } from '../time'

// The species-detail overlay. Reuses the .modal-* design-system classes (loaded
// via avian/application.css); data from /api/species/:sci.
export function SpeciesModal({ sci, onClose }: { sci: string; onClose: () => void }) {
  const { data } = useSpecies(sci)
  const { lang, t } = useLang()

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

  return (
    <div id="detail-modal" className="is-open">
      <div className="modal-backdrop" onClick={onClose} />
      <article className="modal-card">
        <button className="modal-close" aria-label="close" onClick={onClose}>×</button>
        {data && (
          <>
            <div className="modal-grid">
              <div className="modal-img">
                {data.illustrations.map((img) => (
                  <img key={img.label} src={img.url} alt={`${data.en} (${img.label})`} loading="eager" />
                ))}
              </div>
              <div className="modal-info">
                <h2>{name}</h2>
                {subtitle && subtitle !== name && <p className="common">{subtitle}</p>}
                <p className="sci">{data.sci}</p>
                <FollowButton sci={data.sci} variant="full" />
                {cons?.status && (
                  <div className={`cons-line ${cons.status}`}>
                    <span className={`cons-dot ${cons.status}`} />
                    <span className="cons-name">{cons.name} list</span>
                    <span className="cons-note">{cons.note}</span>
                  </div>
                )}
                <div className="modal-stats">
                  <div><span className="n">{data.all_time.toLocaleString()}</span><span className="lbl">{t('all time', 'riamh')}</span></div>
                  <div><span className="n">{data.today.toLocaleString()}</span><span className="lbl">{t('today', 'inniu')}</span></div>
                  <div><span className="n">{ago(data.first_seen)}</span><span className="lbl">{t('first heard', 'chéad chloiste')}</span></div>
                </div>
                {desc && <p className="desc">{desc}</p>}
                {data.song && <audio controls src={data.song} style={{ width: '100%', marginTop: '12px' }} />}
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
          </>
        )}
      </article>
    </div>
  )
}
