'use client'

import { useState } from 'react'
import { TopNav } from '@/components/top-nav'
import { UploadSection } from '@/components/upload-section'
import { LibrarySection } from '@/components/library-section'
import { transcriptionsByUser, users } from '@/lib/mock-data'

type View = 'upload' | 'library'

export default function Page() {
  const [view, setView] = useState<View>('upload')
  const [activeUserId, setActiveUserId] = useState(users[0].id)

  const activeUser = users.find((u) => u.id === activeUserId) ?? users[0]
  const transcriptions = transcriptionsByUser[activeUserId] ?? []

  return (
    <main className="min-h-dvh">
      <TopNav
        view={view}
        onViewChange={setView}
        users={users}
        activeUser={activeUser}
        onUserChange={setActiveUserId}
      />

      {view === 'upload' ? (
        <UploadSection onViewLibrary={() => setView('library')} />
      ) : (
        <LibrarySection user={activeUser} transcriptions={transcriptions} />
      )}
    </main>
  )
}
