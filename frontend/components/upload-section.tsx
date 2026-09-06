'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  AlertTriangle,
  AudioLines,
  Check,
  FileAudio,
  Loader2,
  UploadCloud,
  X,
} from 'lucide-react'
import { cn } from '@/lib/utils'
import { api } from '@/lib/api/client'
import { useJobProgress } from '@/lib/hooks/useJobProgress'
import { probeAudioDuration } from '@/lib/audio'

type Stage = 'uploading' | 'transcribing' | 'done' | 'error'

type UploadItem = {
  id: string
  name: string
  size: string
  progress: number
  stage: Stage
  jobId?: string
  estimatedSeconds?: number | null
}

const MODEL_STORAGE_KEY = 'cadence:preferred-model'
const LANGUAGE_STORAGE_KEY = 'cadence:preferred-language'
const DEFAULT_MODEL = 'small'

const LANGUAGE_OPTIONS: { value: string; label: string }[] = [
  { value: '', label: 'Detectar automáticamente' },
  { value: 'es', label: 'Español' },
  { value: 'en', label: 'Inglés' },
  { value: 'pt', label: 'Portugués' },
  { value: 'fr', label: 'Francés' },
  { value: 'de', label: 'Alemán' },
  { value: 'it', label: 'Italiano' },
]

function formatEstimate(seconds: number): string {
  if (seconds < 60) return `~${Math.max(1, Math.round(seconds))} s`
  return `~${Math.round(seconds / 60)} min`
}

const stageLabel: Record<Stage, string> = {
  uploading: 'Subiendo',
  transcribing: 'Transcribiendo',
  done: 'Listo',
  error: 'Error',
}

function formatSize(bytes: number): string {
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(0)} KB`
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
}

function UploadRow({
  item,
  onUpdate,
  onRemove,
}: {
  item: UploadItem
  onUpdate: (id: string, patch: Partial<UploadItem>) => void
  onRemove: (id: string) => void
}) {
  useJobProgress(
    item.stage === 'transcribing' ? item.jobId : undefined,
    (update) => {
      if (update.status === 'done') {
        onUpdate(item.id, { stage: 'done', progress: 100 })
      } else if (update.status === 'error') {
        onUpdate(item.id, { stage: 'error' })
      } else {
        onUpdate(item.id, { progress: Math.round(update.progress * 100) })
      }
    },
  )

  return (
    <li className="rounded-xl border border-border bg-card p-4">
      <div className="flex items-center gap-3">
        <div
          className={cn(
            'flex size-9 shrink-0 items-center justify-center rounded-lg',
            item.stage === 'done'
              ? 'bg-accent text-accent-foreground'
              : item.stage === 'error'
                ? 'bg-destructive/10 text-destructive'
                : 'bg-muted text-muted-foreground',
          )}
        >
          {item.stage === 'done' ? (
            <Check className="size-4" />
          ) : item.stage === 'error' ? (
            <AlertTriangle className="size-4" />
          ) : (
            <AudioLines className="size-4" />
          )}
        </div>

        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-3">
            <p className="truncate text-sm font-medium">{item.name}</p>
            <span className="shrink-0 font-mono text-xs text-muted-foreground">
              {item.size}
            </span>
          </div>

          <div className="mt-2 flex items-center gap-3">
            <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-muted">
              <div
                className={cn(
                  'h-full rounded-full transition-all duration-300',
                  item.stage === 'done'
                    ? 'bg-accent'
                    : item.stage === 'error'
                      ? 'bg-destructive'
                      : 'bg-primary',
                )}
                style={{ width: `${item.progress}%` }}
              />
            </div>
            <span className="flex w-28 shrink-0 items-center justify-end gap-1.5 font-mono text-xs text-muted-foreground">
              {item.stage !== 'done' && item.stage !== 'error' && (
                <Loader2 className="size-3 animate-spin" />
              )}
              {stageLabel[item.stage]}
              {item.stage !== 'done' && item.stage !== 'error' && ` ${Math.round(item.progress)}%`}
            </span>
          </div>
          {item.stage === 'transcribing' && item.estimatedSeconds != null && (
            <p className="mt-1 text-right font-mono text-[11px] text-muted-foreground">
              estimado {formatEstimate(item.estimatedSeconds)}
            </p>
          )}
        </div>

        <button
          onClick={() => onRemove(item.id)}
          className="flex size-7 shrink-0 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          aria-label={`Quitar ${item.name}`}
        >
          <X className="size-4" />
        </button>
      </div>
    </li>
  )
}

export function UploadSection({ onViewLibrary }: { onViewLibrary: () => void }) {
  const [items, setItems] = useState<UploadItem[]>([])
  const [dragging, setDragging] = useState(false)
  const [model, setModel] = useState(DEFAULT_MODEL)
  const [language, setLanguage] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)

  const { data: models = [] } = useQuery({
    queryKey: ['models'],
    queryFn: api.listModels,
    staleTime: Infinity,
  })

  // Preferences persist in localStorage; read once on mount (window isn't
  // available during the static export's build-time prerender).
  useEffect(() => {
    const storedModel = window.localStorage.getItem(MODEL_STORAGE_KEY)
    if (storedModel) setModel(storedModel)
    const storedLanguage = window.localStorage.getItem(LANGUAGE_STORAGE_KEY)
    if (storedLanguage) setLanguage(storedLanguage)
  }, [])

  useEffect(() => {
    if (models.length > 0 && !models.some((m) => m.name === model)) {
      setModel(models[0].name)
    }
  }, [models, model])

  const handleModelChange = (value: string) => {
    setModel(value)
    window.localStorage.setItem(MODEL_STORAGE_KEY, value)
  }

  const handleLanguageChange = (value: string) => {
    setLanguage(value)
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, value)
  }

  const updateItem = useCallback((id: string, patch: Partial<UploadItem>) => {
    setItems((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it)))
  }, [])

  const removeItem = useCallback((id: string) => {
    setItems((prev) => prev.filter((it) => it.id !== id))
  }, [])

  const startUpload = useCallback(
    (item: UploadItem, file: File) => {
      api
        .uploadJob(file, { model, language: language || null }, (pct) =>
          updateItem(item.id, { progress: pct }),
        )
        .then((job) => {
          updateItem(item.id, {
            jobId: job.id,
            stage: 'transcribing',
            progress: Math.round(job.progress * 100),
          })
        })
        .catch(() => {
          updateItem(item.id, { stage: 'error' })
        })
    },
    [updateItem, model, language],
  )

  const addFiles = useCallback(
    (files: FileList | File[]) => {
      const audio = Array.from(files).filter((f) =>
        /\.(mp3|wav|m4a|ogg|opus|flac|webm|mp4)$/i.test(f.name),
      )
      const speedFactor = models.find((m) => m.name === model)?.speed_factor
      const next = audio.map((f) => ({
        item: {
          id: crypto.randomUUID(),
          name: f.name,
          size: formatSize(f.size),
          progress: 0,
          stage: 'uploading' as Stage,
        },
        file: f,
      }))
      setItems((prev) => [...next.map((n) => n.item), ...prev])
      next.forEach(({ item, file }) => {
        startUpload(item, file)
        if (speedFactor) {
          probeAudioDuration(file).then((duration) => {
            if (duration) updateItem(item.id, { estimatedSeconds: duration * speedFactor })
          })
        }
      })
    },
    [startUpload, updateItem, models, model],
  )

  const activeCount = items.filter((it) => it.stage !== 'done' && it.stage !== 'error').length

  return (
    <section className="mx-auto max-w-5xl px-5 py-10 sm:px-8 sm:py-14">
      <div className="mb-8 max-w-xl">
        <p className="mb-2 font-mono text-xs uppercase tracking-widest text-muted-foreground">
          Paso 01 · Subida
        </p>
        <h1 className="text-pretty text-3xl font-semibold tracking-tight sm:text-4xl">
          Sube un audio y deja que Cadence lo transcriba.
        </h1>
        <p className="mt-3 leading-relaxed text-muted-foreground">
          Arrastra tus archivos o selecciónalos manualmente. Verás el avance en
          tiempo real, desde la subida hasta la transcripción final.
        </p>
      </div>

      <div className="mb-6 flex flex-wrap gap-3">
        <label className="flex items-center gap-2 rounded-full border border-border bg-card px-3.5 py-2 text-sm">
          <span className="text-muted-foreground">Modelo</span>
          <select
            value={model}
            onChange={(e) => handleModelChange(e.target.value)}
            className="cursor-pointer bg-transparent font-medium outline-none"
          >
            {models.map((m) => (
              <option key={m.name} value={m.name}>
                {m.name} — {m.role}
              </option>
            ))}
          </select>
        </label>

        <label className="flex items-center gap-2 rounded-full border border-border bg-card px-3.5 py-2 text-sm">
          <span className="text-muted-foreground">Idioma</span>
          <select
            value={language}
            onChange={(e) => handleLanguageChange(e.target.value)}
            className="cursor-pointer bg-transparent font-medium outline-none"
          >
            {LANGUAGE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      <div
        onDragOver={(e) => {
          e.preventDefault()
          setDragging(true)
        }}
        onDragLeave={() => setDragging(false)}
        onDrop={(e) => {
          e.preventDefault()
          setDragging(false)
          addFiles(e.dataTransfer.files)
        }}
        className={cn(
          'group relative flex flex-col items-center justify-center rounded-2xl border-2 border-dashed px-6 py-14 text-center transition-colors',
          dragging
            ? 'border-ring bg-accent/30'
            : 'border-border bg-card hover:border-ring/60',
        )}
      >
        <div className="flex size-14 items-center justify-center rounded-full bg-accent text-accent-foreground">
          <UploadCloud className="size-6" />
        </div>
        <p className="mt-4 text-base font-medium">
          Arrastra tus audios aquí
        </p>
        <p className="mt-1 text-sm text-muted-foreground">
          MP3, WAV, M4A, OGG, OPUS, FLAC, WEBM, MP4 · hasta 500 MB por archivo
        </p>
        <button
          onClick={() => inputRef.current?.click()}
          className="mt-5 inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90"
        >
          <FileAudio className="size-4" />
          Seleccionar archivos
        </button>
        <input
          ref={inputRef}
          type="file"
          accept="audio/*,.mp3,.wav,.m4a,.ogg,.opus,.flac,.webm,.mp4"
          multiple
          className="hidden"
          onChange={(e) => e.target.files && addFiles(e.target.files)}
        />
      </div>

      {items.length > 0 && (
        <div className="mt-10">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-sm font-semibold">
              En proceso{' '}
              <span className="font-mono text-muted-foreground">
                ({activeCount})
              </span>
            </h2>
            <button
              onClick={onViewLibrary}
              className="text-sm font-medium text-muted-foreground underline-offset-4 hover:text-foreground hover:underline"
            >
              Ver transcripciones
            </button>
          </div>

          <ul className="flex flex-col gap-3">
            {items.map((it) => (
              <UploadRow key={it.id} item={it} onUpdate={updateItem} onRemove={removeItem} />
            ))}
          </ul>
        </div>
      )}
    </section>
  )
}
