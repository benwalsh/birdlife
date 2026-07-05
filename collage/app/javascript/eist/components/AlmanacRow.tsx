import { useLang } from '../lang'
import type { Today } from '../types'

// The almanac — the ambient weather / moon / sun / tide / place readings — as its
// own row directly under the sparkline. Muted mono line-icon + label pairs; never
// emoji. Pre-shaped in Ruby; this just iterates and prints.
export function AlmanacRow({ today }: { today: Today }) {
  const { lang } = useLang()
  if (!today?.footer?.length) return null

  const pick = (item: { en: string; ga: string }) => (lang === 'ga' ? item.ga : item.en)

  return (
    <ul className="today-almanac">
      {today.footer.map((f, i) => (
        <li key={i}>
          <i className={`ti ${f.icon}`} aria-hidden="true" /> {pick(f)}
        </li>
      ))}
    </ul>
  )
}
