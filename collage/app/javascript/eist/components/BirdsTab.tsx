import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { useOverview } from '../api'
import { useLang } from '../lang'
import { Collage } from './Collage'
import { HitsStrip } from './HitsStrip'
import { TodaySpark } from './TodaySpark'
import { AlmanacRow } from './AlmanacRow'
import { BreakingNews } from './BreakingNews'
import { TodayCard } from './TodayCard'

// The condensed masthead's height — the hits strip pins just under it (see .ed-hits
// top:54px), and the sparkline/almanac stack below the hits strip from there.
const MAST_H = 54

// The home page: the collage, then the TODAY block. Scroll past the collage and the
// three strips — the collage's "greatest hits", the sparkline, the almanac — lock and
// stack under the masthead; the TODAY text scrolls beneath. Rankings and lifetime
// numbers live on the stats page.
export function BirdsTab({
  onSelect,
  windowHours,
  onWindow,
  windows,
}: {
  onSelect: (sci: string) => void
  windowHours: number
  onWindow: (hours: number) => void
  windows: [string, number][]
}) {
  const { data, isLoading, isError } = useOverview(windowHours)
  const { t } = useLang()
  const stageRef = useRef<HTMLElement>(null)
  const [pinned, setPinned] = useState(false)
  // The three strips lock and stack under the masthead as you scroll: the collage's
  // hits strip first, then the sparkline sticks below it, then the almanac below that.
  // These are the sticky `top` offsets for the sparkline and almanac — each the running
  // height of the strips above it — measured from what's actually rendered (responsive),
  // so the stack is always flush whatever the masthead/strip heights come out to.
  const [stack, setStack] = useState({ spark: MAST_H, almanac: MAST_H })

  // Pin the hits strip once the collage has scrolled up past the (condensed)
  // masthead. Cheap: reads one bounding rect per scroll frame.
  useEffect(() => {
    const onScroll = () => {
      const stage = stageRef.current
      if (stage) setPinned(stage.getBoundingClientRect().bottom < 72)
    }
    window.addEventListener('scroll', onScroll, { passive: true })
    onScroll()
    return () => window.removeEventListener('scroll', onScroll)
  }, [data])

  // Measure the stack: sparkline sits below masthead + hits; almanac below both. Re-run
  // on data (content changes) and resize (heights change). offsetHeight is unaffected by
  // the strips' own sticky/hidden state, so the hits height reads right even before it pins.
  useLayoutEffect(() => {
    const measure = () => {
      const h = (sel: string) => (document.querySelector(sel) as HTMLElement | null)?.offsetHeight ?? 0
      const hits = h('.ed-hits')
      const spark = h('.today-spark')
      setStack({ spark: MAST_H + hits, almanac: MAST_H + hits + spark })
    }
    measure()
    window.addEventListener('resize', measure)
    return () => window.removeEventListener('resize', measure)
  }, [data])

  if (isLoading || !data) {
    return <p style={{ textAlign: 'center', padding: '60px', color: 'var(--ink-soft)' }}>{isError ? '—' : '…'}</p>
  }

  return (
    <>
      <HitsStrip nodes={data.collage.nodes} onSelect={onSelect} pinned={pinned} />

      <section className="ed-stage" ref={stageRef}>
        <Collage data={data.collage} onSelect={onSelect} />
      </section>

      {data.today?.summary?.en?.length ? (
        <>
          <TodaySpark today={data.today} windows={windows} value={windowHours} onChange={onWindow}
                      stickyTop={stack.spark} />
          <AlmanacRow today={data.today} stickyTop={stack.almanac} />
          <BreakingNews items={data.breaking} onSelect={onSelect} />
          <TodayCard today={data.today} />
        </>
      ) : (
        <p className="ed-empty">{t('Ag éisteacht… nothing heard yet.', 'Ag éisteacht… faic cloiste fós.')}</p>
      )}
    </>
  )
}
