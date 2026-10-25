import type { Transcription } from './api/view-models'

export type ExportFormat = 'txt' | 'md' | 'json' | 'srt' | 'vtt' | 'pdf'

async function downloadFromApi(jobId: string, format: ExportFormat, fallbackFilename: string) {
  const res = await fetch(`/api/jobs/${jobId}/export?format=${format}`)
  if (!res.ok) {
    throw new Error(`export failed: ${res.status}`)
  }
  const disposition = res.headers.get('Content-Disposition')
  const utf8Match = disposition?.match(/filename\*=UTF-8''([^;]+)/)
  const asciiMatch = disposition?.match(/filename="([^"]+)"/)
  const filename = (utf8Match ? decodeURIComponent(utf8Match[1]) : asciiMatch?.[1]) ?? fallbackFilename

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
