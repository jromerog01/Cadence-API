'use client'

import { useEffect, useState } from 'react'
import { Loader2 } from 'lucide-react'
import { TopNav } from '@/components/top-nav'
import { UploadSection } from '@/components/upload-section'
import { LibrarySection } from '@/components/library-section'
import { LoginScreen } from '@/components/login-screen'
import { api, type AuthUser } from '@/lib/api/client'

type View = 'upload' | 'library'

export default function Page() {
  const [view, setView] = useState<View>('upload')
  const [user, setUser] = useState<AuthUser | null | undefined>(undefined)

  useEffect(() => {
    api.me().then(setUser)
  }, [])

  if (user === undefined) {
    return (
      <main className="flex min-h-dvh items-center justify-center">
        <Loader2 className="size-6 animate-spin text-muted-foreground" />
      </main>
    )
  }

  if (user === null) {
    return <LoginScreen onLogin={setUser} />
  }

  return (
    <main className="min-h-dvh">
      <TopNav
        view={view}
        onViewChange={setView}
        user={user}
        onLogout={() => api.logout().then(() => setUser(null))}
      />

      {view === 'upload' ? (
        <UploadSection onViewLibrary={() => setView('library')} />
      ) : (
        <LibrarySection user={user} />
      )}
    </main>
  )
}
