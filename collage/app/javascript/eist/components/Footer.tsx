import { useLang } from '../lang'

// The place is the instance's own — from config/API via the bootstrap, never a
// hard-coded location. Absent (unconfigured) → just the station line, no place.
export function Footer({ place }: { place: { en: string; ga: string } | null }) {
  const { t, lang } = useLang()
  const here = place ? (lang === 'ga' ? place.ga : place.en) : null
  return (
    <footer className="ed-foot">
      <span>{t('Éist · Listening Station', 'Éist · Stáisiún Éisteachta')}</span>
      {here && <span className="dot">·</span>}
      {here && <span>{here}</span>}
    </footer>
  )
}
