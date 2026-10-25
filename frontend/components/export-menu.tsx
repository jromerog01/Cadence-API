'use client'

import { useEffect, useRef, useState } from 'react'
import { ChevronDown, Download, FileCode, FileJson, FileText, FileType, Subtitles } from 'lucide-react'
import { cn } from '@/lib/utils'
import {
  exportTranscription,
  type ExportFormat,
} from '@/lib/export-utils'
import type { Transcription } from '@/lib/api/view-models'

const options: { format: ExportFormat; label: string; hint: string; icon: typeof FileText }[] = [
  { format: 'txt', label: 'Texto plano', hint: '.txt', icon: FileText },
  { format: 'md', label: 'Markdown', hint: '.md', icon: FileCode },
  { format: 'json', label: 'JSON', hint: '.json', icon: FileJson },
  { format: 'srt', label: 'Subtítulos SRT', hint: '.srt', icon: Subtitles },
  { format: 'vtt', label: 'Subtítulos VTT', hint: '.vtt', icon: Subtitles },
  { format: 'pdf', label: 'Documento', hint: '.pdf', icon: FileType },
]

export function ExportMenu({ transcription }: { transcription: Transcription }) {
  const [open, setOpen] = useState(false)
  const [error, setError] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="inline-flex items-center gap-1.5 rounded-full border border-border bg-card px-3.5 py-1.5 text-sm font-medium transition-colors hover:bg-muted"
      >
        <Download className="size-3.5" />
        Exportar
        <ChevronDown
          className={cn('size-3.5 transition-transform', open && 'rotate-180')}
        />
      </button>

      {open && (
        <div className="absolute right-0 top-full z-20 mt-2 w-52 overflow-hidden rounded-xl border border-border bg-popover p-1.5 shadow-lg">
          {options.map((opt) => {
            const Icon = opt.icon
            return (
              <button
                key={opt.format}
                onClick={() => {
                  setOpen(false)
                  setError(false)
                  exportTranscription(transcription, opt.format).catch(() => setError(true))
                }}
                className="flex w-full items-center gap-3 rounded-lg px-2.5 py-2 text-left text-sm transition-colors hover:bg-muted"
              >
                <Icon className="size-4 text-muted-foreground" />
                <span className="flex-1">{opt.label}</span>
                <span className="font-mono text-xs text-muted-foreground">
                  {opt.hint}
                </span>
              </button>
            )
          })}
        </div>
      )}
      {error && (
        <p className="absolute right-0 top-full z-20 mt-1 w-44 text-right text-xs text-destructive">
          No se pudo exportar. Intenta de nuevo.
        </p>
      )}
    </div>
  )
}
