import type { Job } from '@/lib/api/client'

export type TranscriptSegment = {
  start: string
  speaker: string
  text: string
}

export type Transcription = {
  id: string
  title: string
  fileName: string
  createdAt: string
  duration: string
  language: string
  words: number
  status: 'listo' | 'procesando' | 'error'
  errorMessage?: string | null
  segments: TranscriptSegment[]
}

export type User = {
  id: string
  name: string
  email: string
  initials: string
}

export function formatDuration(totalSeconds: number | null): string {
  if (totalSeconds == null || Number.isNaN(totalSeconds)) return '--:--'
  const seconds = Math.round(totalSeconds)
  const minutes = Math.floor(seconds / 60)
  const remaining = seconds % 60
  return `${minutes.toString().padStart(2, '0')}:${remaining.toString().padStart(2, '0')}`
}

function statusOf(job: Job): Transcription['status'] {
  if (job.status === 'done') return 'listo'
  if (job.status === 'error') return 'error'
  return 'procesando'
}

export function toViewModel(job: Job): Transcription {
  const words = job.segments.reduce(
    (count, s) => count + s.text.split(/\s+/).filter(Boolean).length,
    0,
  )
  return {
    id: job.id,
    title: job.original_filename.replace(/\.[^/.]+$/, ''),
    fileName: job.original_filename,
    createdAt: job.created_at,
    duration: formatDuration(job.duration_seconds),
    language: job.detected_language ?? job.language ?? 'Detectando…',
    words,
    status: statusOf(job),
    errorMessage: job.error_message,
    segments: job.segments.map((s) => ({
      start: formatDuration(s.start_seconds),
      speaker: s.speaker ?? '',
      text: s.text,
    })),
  }
}
