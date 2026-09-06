import { z } from 'zod'

export const SegmentSchema = z.object({
  idx: z.number(),
  start_seconds: z.number(),
  end_seconds: z.number(),
  text: z.string(),
  speaker: z.string().nullable(),
})

export const JobSchema = z.object({
  id: z.string(),
  original_filename: z.string(),
  duration_seconds: z.number().nullable(),
  model: z.string(),
  language: z.string().nullable(),
  detected_language: z.string().nullable(),
  status: z.enum(['queued', 'processing', 'done', 'error']),
  progress: z.number(),
  stage: z.enum(['normalizing', 'transcribing', 'diarizing']).nullable(),
  error_message: z.string().nullable(),
  created_at: z.string(),
  segments: z.array(SegmentSchema).default([]),
})

export type Job = z.infer<typeof JobSchema>
export type JobSegment = z.infer<typeof SegmentSchema>

export const ModelSchema = z.object({
  name: z.string(),
  ram_gb: z.number(),
  speed_factor: z.number(),
  role: z.string(),
})

export type WhisperModel = z.infer<typeof ModelSchema>

export const AuthUserSchema = z.object({
  id: z.string(),
  email: z.string(),
  display_name: z.string(),
})

export type AuthUser = z.infer<typeof AuthUserSchema>

const API_BASE = '/api'

async function parseOrThrow<T>(schema: z.ZodType<T>, res: Response): Promise<T> {
  if (!res.ok) {
    throw new Error(`API error ${res.status}`)
  }
  return schema.parse(await res.json())
}

export type UploadOptions = {
  model?: string
  language?: string | null
}

const InitUploadSchema = z.object({
  upload_id: z.string(),
  chunk_size: z.number(),
  total_parts: z.number(),
})

function putChunk(url: string, blob: Blob, onLoaded: (loaded: number) => void): Promise<void> {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open('PUT', url)
    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable) onLoaded(e.loaded)
    }
    xhr.onload = () => {
      if (xhr.status >= 400) reject(new Error(`chunk upload failed: ${xhr.status}`))
      else resolve()
    }
    xhr.onerror = () => reject(new Error('network error'))
    xhr.send(blob)
  })
}

// A flaky mobile connection is exactly what chunked upload exists for, so a
// failed chunk gets a few retries with backoff before giving up the whole
// upload.
async function putChunkWithRetry(
  url: string,
  blob: Blob,
  onLoaded: (loaded: number) => void,
  attempts = 3,
): Promise<void> {
  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      await putChunk(url, blob, onLoaded)
      return
    } catch (err) {
      if (attempt === attempts) throw err
      await new Promise((r) => setTimeout(r, 500 * attempt))
    }
  }
}

// Uploads in 8MB chunks via /api/uploads/* instead of one multipart POST:
// Cloudflare's free plan caps a single request at 100MB, and a WAV or a
// long recording can easily exceed that.
async function uploadJob(
  file: File,
  options: UploadOptions,
  onProgress: (pct: number) => void,
): Promise<Job> {
  const initRes = await fetch(`${API_BASE}/uploads`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      filename: file.name,
      size_bytes: file.size,
      model: options.model,
      language: options.language,
    }),
  })
  const { upload_id, chunk_size, total_parts } = await parseOrThrow(InitUploadSchema, initRes)

  let uploadedBytes = 0
  for (let part = 0; part < total_parts; part++) {
    const start = part * chunk_size
    const blob = file.slice(start, Math.min(start + chunk_size, file.size))
    const baseBytes = uploadedBytes
    await putChunkWithRetry(`${API_BASE}/uploads/${upload_id}/parts/${part}`, blob, (loaded) => {
      onProgress(((baseBytes + loaded) / file.size) * 100)
    })
    uploadedBytes += blob.size
    onProgress((uploadedBytes / file.size) * 100)
  }

  const completeRes = await fetch(`${API_BASE}/uploads/${upload_id}/complete`, { method: 'POST' })
  return parseOrThrow(JobSchema, completeRes)
}

export const api = {
  listJobs: () =>
    fetch(`${API_BASE}/jobs`).then((res) => parseOrThrow(z.array(JobSchema), res)),

  getJob: (id: string) =>
    fetch(`${API_BASE}/jobs/${id}`).then((res) => parseOrThrow(JobSchema, res)),

  deleteJob: (id: string) =>
    fetch(`${API_BASE}/jobs/${id}`, { method: 'DELETE' }).then((res) => {
      if (!res.ok) throw new Error(`delete failed: ${res.status}`)
    }),

  listModels: () =>
    fetch(`${API_BASE}/models`).then((res) => parseOrThrow(z.array(ModelSchema), res)),

  uploadJob,

  me: (): Promise<AuthUser | null> =>
    fetch(`${API_BASE}/auth/me`).then((res) => {
      if (res.status === 401) return null
      return parseOrThrow(AuthUserSchema, res)
    }),

  login: (email: string, password: string) =>
    fetch(`${API_BASE}/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password }),
    }).then((res) => {
      if (!res.ok) throw new Error('Credenciales inválidas')
      return parseOrThrow(AuthUserSchema, res)
    }),

  logout: () => fetch(`${API_BASE}/auth/logout`, { method: 'POST' }).then(() => undefined),
}
