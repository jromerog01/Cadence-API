'use client'

import { useState } from 'react'
import { TopNav } from '@/components/top-nav'
import { UploadSection } from '@/components/upload-section'
import { LibrarySection } from '@/components/library-section'
import type { User } from '@/lib/api/view-models'

type View = 'upload' | 'library'

// Fase 8 reemplaza esto por la sesión real; hasta entonces todos los
// trabajos pertenecen al usuario `default` sembrado en la migración inicial.
const DEFAULT_USER: User = {
  id: 'default',
  name: 'Default',
  email: 'default@cadence.local',
  initials: 'DF',
}

export default function Page() {
  const [view, setView] = useState<View>('upload')

  return (
    <main className="min-h-dvh">
      <TopNav
        view={view}
        onViewChange={setView}
        users={[DEFAULT_USER]}
        activeUser={DEFAULT_USER}
        onUserChange={() => {}}
      />

      {view === 'upload' ? (
        <UploadSection onViewLibrary={() => setView('library')} />
      ) : (
        <LibrarySection user={DEFAULT_USER} />
      )}
    </main>
  )
}
