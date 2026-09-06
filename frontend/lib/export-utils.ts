import type { Transcription } from './api/view-models'

export type ExportFormat = 'txt' | 'md' | 'pdf'

function plainText(t: Transcription): string {
  const header = `${t.title}\nArchivo: ${t.fileName}\nDuración: ${t.duration} · ${t.words} palabras · ${t.language}\n\n`
  const body = t.segments
    .map((s) => `[${s.start}] ${s.speaker}: ${s.text}`)
    .join('\n\n')
  return header + body
}

function markdown(t: Transcription): string {
  const header = `# ${t.title}\n\n> Archivo: \`${t.fileName}\`  \n> Duración: ${t.duration} · ${t.words} palabras · ${t.language}\n\n---\n\n`
  const body = t.segments
    .map((s) => `**${s.speaker}** \`${s.start}\`\n\n${s.text}`)
    .join('\n\n')
  return header + body
}

function download(filename: string, content: string, mime: string) {
  const blob = new Blob([content], { type: mime })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function exportPdf(t: Transcription) {
  const win = window.open('', '_blank', 'width=800,height=900')
  if (!win) return
  const rows = t.segments
    .map(
      (s) => `
        <div class="seg">
          <div class="meta"><span class="spk">${s.speaker}</span><span class="ts">${s.start}</span></div>
          <p>${s.text}</p>
        </div>`,
    )
    .join('')
  win.document.write(`
    <!doctype html><html><head><meta charset="utf-8" />
    <title>${t.title}</title>
    <style>
      * { box-sizing: border-box; }
      body { font-family: -apple-system, system-ui, sans-serif; color: #232320; margin: 48px; line-height: 1.6; }
      h1 { font-size: 24px; margin: 0 0 6px; }
      .sub { color: #6b6b64; font-size: 13px; margin-bottom: 28px; border-bottom: 1px solid #e6e6e0; padding-bottom: 18px; }
      .seg { margin-bottom: 20px; }
      .meta { display: flex; gap: 10px; align-items: baseline; margin-bottom: 4px; }
      .spk { font-weight: 600; font-size: 13px; }
      .ts { color: #9a9a92; font-size: 11px; font-family: ui-monospace, monospace; }
      p { margin: 0; font-size: 14px; }
    </style></head>
    <body>
      <h1>${t.title}</h1>
      <div class="sub">${t.fileName} · ${t.duration} · ${t.words} palabras · ${t.language}</div>
      ${rows}
      <script>window.onload = function () { window.print(); }</script>
    </body></html>`)
  win.document.close()
}

export function exportTranscription(t: Transcription, format: ExportFormat) {
  const base = t.fileName.replace(/\.[^.]+$/, '')
  if (format === 'txt') {
    download(`${base}.txt`, plainText(t), 'text/plain;charset=utf-8')
  } else if (format === 'md') {
    download(`${base}.md`, markdown(t), 'text/markdown;charset=utf-8')
  } else {
    exportPdf(t)
  }
}
