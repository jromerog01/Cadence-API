'use client'

import { useEffect, useRef } from 'react'
import { api } from '@/lib/api/client'

export type JobProgressUpdate = {
  status: 'processing' | 'done' | 'error'
  progress: number
  stage: string | null
}

const POLL_FALLBACK_INTERVAL_MS = 2000

/**
 * Subscribes to /api/jobs/{id}/events (SSE) for as long as jobId is set,
 * falling back to polling if the EventSource itself fails (broken proxy,
 * browser without SSE support). Note: EventSource dispatches type "error"
 * both for our server's named `event: error` (job failed — MessageEvent
 * with `.data`) and for a transport failure (plain Event, no `.data`), so
 * onerror below has to tell the two apart.
 */
export function useJobProgress(
  jobId: string | undefined,
  onUpdate: (update: JobProgressUpdate) => void,
) {
  const onUpdateRef = useRef(onUpdate)
  onUpdateRef.current = onUpdate

  useEffect(() => {
    if (!jobId) return

    let stopped = false
    let pollInterval: ReturnType<typeof setInterval> | null = null
    const source = new EventSource(`/api/jobs/${jobId}/events`)

    const stopPolling = () => {
      if (pollInterval) {
        clearInterval(pollInterval)
        pollInterval = null
      }
    }

    const finish = (status: 'done' | 'error') => {
      stopped = true
      stopPolling()
      source.close()
      onUpdateRef.current({ status, progress: status === 'done' ? 1 : 0, stage: null })
    }

    const startPollingFallback = () => {
      if (stopped || pollInterval) return
      pollInterval = setInterval(() => {
        api
          .getJob(jobId)
          .then((job) => {
            if (job.status === 'done' || job.status === 'error') {
              stopped = true
              stopPolling()
              onUpdateRef.current({ status: job.status, progress: job.progress, stage: job.stage })
            } else {
              onUpdateRef.current({ status: 'processing', progress: job.progress, stage: job.stage })
            }
          })
          .catch(() => {})
      }, POLL_FALLBACK_INTERVAL_MS)
    }

    source.addEventListener('progress', (e) => {
      const data = JSON.parse((e as MessageEvent).data)
      onUpdateRef.current({ status: 'processing', progress: data.progress, stage: data.stage })
    })
    source.addEventListener('done', () => finish('done'))

    source.onerror = (e) => {
      if (stopped) return
      if ((e as MessageEvent).data) {
        // our server's named `event: error` (the job itself failed)
        finish('error')
        return
      }
      // transport-level failure; EventSource would otherwise retry forever
      source.close()
      startPollingFallback()
    }

    return () => {
      stopped = true
      stopPolling()
      source.close()
    }
  }, [jobId])
}
