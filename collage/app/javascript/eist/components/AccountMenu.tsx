import { useEffect, useRef, useState } from 'react'
import type { CurrentUser } from '../types'

function csrf(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? ''
}

// The account avatar + dropdown. Sign in/out are real Rails form posts (OmniAuth
// needs a CSRF-protected POST); the current user comes from the bootstrap.
export function AccountMenu({ user }: { user: CurrentUser | null }) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const onDoc = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    const onEsc = (e: KeyboardEvent) => e.key === 'Escape' && setOpen(false)
    document.addEventListener('click', onDoc)
    document.addEventListener('keydown', onEsc)
    return () => {
      document.removeEventListener('click', onDoc)
      document.removeEventListener('keydown', onEsc)
    }
  }, [])

  // Signed out is the common case: a plain mono "Sign in" link in the masthead
  // voice, not a chromed icon button. It posts straight to Google (OmniAuth needs a
  // CSRF-protected POST), so there's no dropdown to open.
  if (!user) {
    return (
      <form className="ed-signin" method="post" action="/auth/google_oauth2">
        <input type="hidden" name="authenticity_token" value={csrf()} />
        <button className="ed-signin-btn" type="submit">Sign in</button>
      </form>
    )
  }

  return (
    <div className="ed-user" ref={ref}>
      <button
        className="ed-avatar"
        aria-label="Account"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={(e) => { e.stopPropagation(); setOpen((o) => !o) }}
      >
        {user.avatar_url ? (
          <img className="ed-avatar-img" src={user.avatar_url} alt={user.name} referrerPolicy="no-referrer" />
        ) : (
          <span className="ed-avatar-initial">{user.name.trim().charAt(0).toUpperCase()}</span>
        )}
      </button>
      <div className={`ed-menu${open ? ' is-open' : ''}`} role="menu">
        <div className="ed-menu-user">
          <span className="ed-menu-name">{user.name}</span>
          {user.email && user.email !== user.name && <span className="ed-menu-sub">{user.email}</span>}
        </div>
        <a className="ed-menu-item" href="/account" role="menuitem">Account</a>
        <form method="post" action="/logout">
          <input type="hidden" name="_method" value="delete" />
          <input type="hidden" name="authenticity_token" value={csrf()} />
          <button className="ed-menu-item ed-menu-btn" type="submit" role="menuitem">Sign out</button>
        </form>
      </div>
    </div>
  )
}
