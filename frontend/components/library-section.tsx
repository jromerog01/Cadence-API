'use client'

import { useMemo, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertCircle, ChevronDown, Clock, FileAudio, Loader2, Search, Trash2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import { ExportMenu } from '@/components/export-menu'
import { api, type AuthUser } from '@/lib/api/client'
import { toViewModel, type Transcription } from '@/lib/api/view-models'

const STAGE_LABELS: Record<string, string> = {
  normalizing: 'normalizando',
  transcribing: 'transcribiendo',
  diarizing: 'diarizando',
}

function formatDate(iso: string): string {
  return new Date(iso).toLocaleDateString('es', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  })
}

function TranscriptionRow({ t, onDelete }: { t: Transcription; onDelete: (id: string) => void }) {
  const [open, setOpen] = useState(false)
  const processing = t.status === 'procesando'
  const errored = t.status === 'error'
  const expandable = t.status === 'listo' || processing

  // The jobs list endpoint never includes segment text (too expensive to
  // load for every row), so viewing a transcript requires fetching the
  // full job detail — polled while processing to show text as it's
  // transcribed, fetched once for finished jobs.
  const { data: detail } = useQuery({
    queryKey: ['job', t.id],
    queryFn: () => api.getJob(t.id).then(toViewModel),
    enabled: open && expandable,
    refetchInterval: open && processing ? 2000 : false,
  })
  const segments = detail?.segments ?? []

  return (
    // No overflow-hidden here: it would clip the export dropdown/error
    // tooltip, which are absolutely positioned and can extend past this
    // card's own box (that's what was cutting them off on narrow screens).
    <article className="rounded-xl border border-border bg-card">
      <div className="flex flex-col gap-4 p-5 sm:flex-row sm:items-center">
        <div className="flex size-10 shrink-0 items-center justify-center rounded-lg bg-muted text-muted-foreground">
          <FileAudio className="size-5" />
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
            <h3 className="text-pretty text-base font-semibold tracking-tight">
              {t.title}
            </h3>
            {processing && (
              <span className="inline-flex items-center gap-1 rounded-full bg-muted px-2 py-0.5 font-mono text-[11px] text-muted-foreground">
                <Loader2 className="size-3 animate-spin" />
                {t.stage && STAGE_LABELS[t.stage] ? STAGE_LABELS[t.stage] : 'procesando'}
                {' · '}
                {Math.round(t.progress * 100)}%
              </span>
            )}
            {errored && (
              <span
                className="inline-flex items-center gap-1 rounded-full bg-destructive/10 px-2 py-0.5 font-mono text-[11px] text-destructive"
                title={t.errorMessage ?? undefined}
              >
                <AlertCircle className="size-3" />
                error
              </span>
            )}
          </div>
          <div className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-0.5 font-mono text-xs text-muted-foreground">
            <span className="inline-flex items-center gap-1">
              <Clock className="size-3" />
              {t.duration}
            </span>
            <span>{t.words.toLocaleString('es')} palabras</span>
            <span>{formatDate(t.createdAt)}</span>
          </div>
          {processing && (
            <div className="mt-2 h-1.5 w-full max-w-xs overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-foreground transition-all"
                style={{ width: `${Math.round(t.progress * 100)}%` }}
              />
            </div>
          )}
        </div>

        <div className="flex shrink-0 items-center gap-2">
          {t.status === 'listo' && <ExportMenu transcription={t} />}
          <button
            onClick={() => setOpen((v) => !v)}
            disabled={!expandable}
            aria-expanded={open}
            className="inline-flex items-center gap-1.5 rounded-full px-3.5 py-1.5 text-sm font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground disabled:opacity-40"
          >
            {open ? 'Ocultar' : 'Ver'}
            <ChevronDown
              className={cn('size-3.5 transition-transform', open && 'rotate-180')}
            />
          </button>
          <button
            onClick={() => onDelete(t.id)}
            aria-label={`Eliminar ${t.title}`}
            title={processing ? 'Cancelar' : 'Eliminar'}
            className="flex size-8 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
          >
            <Trash2 className="size-4" />
          </button>
        </div>
      </div>

      {open && expandable && (
        <div className="overflow-hidden rounded-b-xl border-t border-border bg-secondary/40 px-5 py-5">
          {segments.length === 0 && processing && (
            <p className="text-sm text-muted-foreground">
              Esperando los primeros segmentos…
            </p>
          )}
          <ul className="flex flex-col gap-5">
            {segments.map((s, i) => (
              <li key={i} className="flex gap-4">
                <div className="w-16 shrink-0 pt-0.5 text-right">
                  <span className="font-mono text-xs text-muted-foreground">
                    {s.start}
                  </span>
                </div>
                <div className="min-w-0 flex-1 border-l border-border pl-4">
                  {s.speaker && (
                    <p className="mb-1 text-xs font-semibold text-accent-foreground">
                      {s.speaker}
                    </p>
                  )}
                  <p className="text-pretty leading-relaxed text-foreground">
                    {s.text}
                  </p>
                </div>
              </li>
            ))}
          </ul>
        </div>
      )}
    </article>
  )
}

export function LibrarySection({ user }: { user: AuthUser }) {
  const [query, setQuery] = useState('')
  const queryClient = useQueryClient()

  const { data: jobs = [] } = useQuery({
    queryKey: ['jobs'],
    queryFn: api.listJobs,
    refetchInterval: 2000,
  })

  const handleDelete = (id: string) => {
    api.deleteJob(id).then(() => queryClient.invalidateQueries({ queryKey: ['jobs'] }))
  }

  const transcriptions = useMemo(() => jobs.map(toViewModel), [jobs])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return transcriptions
    return transcriptions.filter(
      (t) =>
        t.title.toLowerCase().includes(q) ||
        t.fileName.toLowerCase().includes(q),
    )
  }, [query, transcriptions])

  const ready = transcriptions.filter((t) => t.status === 'listo').length

  return (
    <section className="mx-auto max-w-5xl px-5 py-10 sm:px-8 sm:py-14">
      <div className="mb-8 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="mb-2 font-mono text-xs uppercase tracking-widest text-muted-foreground">
            Paso 02 · Biblioteca
          </p>
          <h1 className="text-pretty text-3xl font-semibold tracking-tight sm:text-4xl">
            Transcripciones de {user.display_name.split(' ')[0]}
          </h1>
          <p className="mt-3 leading-relaxed text-muted-foreground">
            {ready} transcripciones listas · exporta cualquiera como TXT,
            Markdown o PDF.
          </p>
        </div>
      </div>

      <div className="relative mb-6">
        <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Buscar por título o archivo..."
          className="w-full rounded-full border border-border bg-card py-2.5 pl-10 pr-4 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40"
        />
      </div>

      {filtered.length === 0 ? (
        <div className="rounded-xl border border-dashed border-border bg-card px-6 py-16 text-center">
          <p className="text-sm text-muted-foreground">
            No hay transcripciones que coincidan con tu búsqueda.
          </p>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          {filtered.map((t) => (
            <TranscriptionRow key={t.id} t={t} onDelete={handleDelete} />
          ))}
        </div>
      )}
    </section>
  )
}
