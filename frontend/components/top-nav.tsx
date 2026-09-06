'use client'

import { AudioLines, LogOut } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { AuthUser } from '@/lib/api/client'

type View = 'upload' | 'library'

function initialsOf(name: string): string {
  const parts = name.trim().split(/\s+/)
  return parts
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('')
}

export function TopNav({
  view,
  onViewChange,
  user,
  onLogout,
}: {
  view: View
  onViewChange: (v: View) => void
  user: AuthUser
  onLogout: () => void
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

        <div className="flex items-center gap-2">
          <span className="flex size-8 items-center justify-center rounded-full bg-accent font-mono text-xs font-semibold text-accent-foreground">
            {initialsOf(user.display_name)}
          </span>
          <span className="hidden text-sm font-medium sm:inline">{user.display_name}</span>
          <button
            onClick={onLogout}
            aria-label="Cerrar sesión"
            title="Cerrar sesión"
            className="flex size-8 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <LogOut className="size-4" />
          </button>
        </div>
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
