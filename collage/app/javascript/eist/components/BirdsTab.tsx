import { useEffect, useRef, useState } from 'react'
import { useOverview } from '../api'
import { useLang } from '../lang'
import { Collage } from './Collage'
import { HitsStrip } from './HitsStrip'
import { TodaySpark } from './TodaySpark'
import { AlmanacRow } from './AlmanacRow'
import { BreakingNews } from './BreakingNews'
import { TodayCard } from './TodayCard'

// The home page: the collage, then the TODAY block. Scroll past the collage and it
// locks into a horizontal "greatest hits" strip pinned below the masthead. Rankings
// and lifetime numbers live on the stats page.
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
          <TodaySpark today={data.today} windows={windows} value={windowHours} onChange={onWindow} />
          <AlmanacRow today={data.today} />
          <BreakingNews items={data.breaking} onSelect={onSelect} />
          <TodayCard today={data.today} />
        </>
      ) : (
        <p className="ed-empty">{t('Ag éisteacht… nothing heard yet.', 'Ag éisteacht… faic cloiste fós.')}</p>
      )}
    </>
  )
}
