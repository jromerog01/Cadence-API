import type { Transcription } from './api/view-models'

export type ExportFormat = 'txt' | 'md' | 'json' | 'srt' | 'vtt' | 'pdf'

async function downloadFromApi(jobId: string, format: ExportFormat, fallbackFilename: string) {
  const res = await fetch(`/api/jobs/${jobId}/export?format=${format}`)
  if (!res.ok) {
    throw new Error(`export failed: ${res.status}`)
  }
  const disposition = res.headers.get('Content-Disposition')
  const match = disposition?.match(/filename="([^"]+)"/)
  const filename = match?.[1] ?? fallbackFilename

  const blob = await res.blob()
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

export function exportTranscription(t: Transcription, format: ExportFormat) {
  const base = t.fileName.replace(/\.[^.]+$/, '')
  return downloadFromApi(t.id, format, `${base}.${format}`)
}
