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

export const api = {
  listJobs: () =>
    fetch(`${API_BASE}/jobs`).then((res) => parseOrThrow(z.array(JobSchema), res)),

  getJob: (id: string) =>
    fetch(`${API_BASE}/jobs/${id}`).then((res) => parseOrThrow(JobSchema, res)),

  listModels: () =>
    fetch(`${API_BASE}/models`).then((res) => parseOrThrow(z.array(ModelSchema), res)),

  uploadJob: (file: File, options: UploadOptions, onProgress: (pct: number) => void) =>
    new Promise<Job>((resolve, reject) => {
      const xhr = new XMLHttpRequest()
      xhr.open('POST', `${API_BASE}/jobs`)
      xhr.upload.onprogress = (e) => {
        if (e.lengthComputable) onProgress((e.loaded / e.total) * 100)
      }
      xhr.onload = () => {
        try {
          if (xhr.status >= 400) {
            reject(new Error(`upload failed: ${xhr.status}`))
            return
          }
          resolve(JobSchema.parse(JSON.parse(xhr.responseText)))
        } catch (err) {
          reject(err)
        }
      }
      xhr.onerror = () => reject(new Error('network error'))
      const form = new FormData()
      form.append('file', file)
      if (options.model) form.append('model', options.model)
      if (options.language) form.append('language', options.language)
      xhr.send(form)
    }),
}
