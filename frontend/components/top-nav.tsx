'use client'

import { AudioLines } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { User } from '@/lib/mock-data'

type View = 'upload' | 'library'

export function TopNav({
  view,
  onViewChange,
  users,
  activeUser,
  onUserChange,
}: {
  view: View
  onViewChange: (v: View) => void
  users: User[]
  activeUser: User
  onUserChange: (id: string) => void
}) {
  const tabs: { id: View; label: string }[] = [
    { id: 'upload', label: 'Subir audio' },
    { id: 'library', label: 'Transcripciones' },
  ]

  return (
    <header className="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-5xl items-center justify-between px-5 sm:px-8">
        <div className="flex items-center gap-2.5">
          <div className="flex size-8 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <AudioLines className="size-4" />
          </div>
          <span className="text-base font-semibold tracking-tight">Cadence</span>
        </div>

        <nav className="hidden items-center gap-1 rounded-full border border-border bg-card p-1 sm:flex">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => onViewChange(tab.id)}
              className={cn(
                'rounded-full px-4 py-1.5 text-sm font-medium transition-colors',
                view === tab.id
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {tab.label}
            </button>
          ))}
        </nav>

        <label className="flex items-center gap-2">
          <span className="sr-only">Usuario activo</span>
          <span className="flex size-8 items-center justify-center rounded-full bg-accent font-mono text-xs font-semibold text-accent-foreground">
            {activeUser.initials}
          </span>
          <select
            value={activeUser.id}
            onChange={(e) => onUserChange(e.target.value)}
            className="cursor-pointer rounded-md bg-transparent py-1 pr-1 text-sm font-medium outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      <nav className="flex items-center gap-1 border-t border-border px-5 py-2 sm:hidden">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => onViewChange(tab.id)}
            className={cn(
              'flex-1 rounded-full px-4 py-1.5 text-sm font-medium transition-colors',
              view === tab.id
                ? 'bg-primary text-primary-foreground'
                : 'text-muted-foreground',
            )}
          >
            {tab.label}
          </button>
        ))}
      </nav>
    </header>
  )
}
