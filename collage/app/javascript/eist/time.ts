// Detection timestamps arrive as "YYYY-MM-DD HH:MM:SS" (no zone) or ISO8601.
function parse(value: string): number {
  return new Date(value.includes('T') ? value : value.replace(' ', 'T')).getTime()
}

// Compact relative time, matching the old server helper: "now", "8m ago", "3h ago".
export function ago(value: string | null): string {
  if (!value) return '—'
  const secs = (Date.now() - parse(value)) / 1000
  if (secs < 60) return 'now'
  if (secs < 3600) return `${Math.floor(secs / 60)}m ago`
  if (secs < 86_400) return `${Math.floor(secs / 3600)}h ago`
  return `${Math.floor(secs / 86_400)}d ago`
}

export function shortDate(value: string | null): string {
  if (!value) return ''
  return new Date(value.includes('T') ? value : value.replace(' ', 'T'))
    .toLocaleDateString('en-IE', { day: 'numeric', month: 'short', year: 'numeric' })
}

// "2 Jul · 22:05" for the modal's recordings list.
export function stamp(value: string | null): string {
  if (!value) return ''
  const d = new Date(value.includes('T') ? value : value.replace(' ', 'T'))
  const date = d.toLocaleDateString('en-IE', { day: 'numeric', month: 'short' })
  const time = d.toLocaleTimeString('en-IE', { hour: '2-digit', minute: '2-digit', hour12: false })
  return `${date} · ${time}`
}
