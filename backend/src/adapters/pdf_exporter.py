from weasyprint import HTML

from domain.exporters._util import format_duration
from domain.models import Job

_STYLE = """
* { box-sizing: border-box; }
body { font-family: sans-serif; color: #232320; margin: 48px; line-height: 1.6; }
h1 { font-size: 24px; margin: 0 0 6px; }
.sub { color: #6b6b64; font-size: 13px; margin-bottom: 28px; border-bottom: 1px solid #e6e6e0; padding-bottom: 18px; }
.seg { margin-bottom: 20px; }
.meta { display: flex; gap: 10px; align-items: baseline; margin-bottom: 4px; }
.spk { font-weight: 600; font-size: 13px; }
.ts { color: #9a9a92; font-size: 11px; font-family: monospace; }
p { margin: 0; font-size: 14px; }
"""


def _escape(text: str) -> str:
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def to_pdf(job: Job) -> bytes:
    language = job.detected_language or job.language or "desconocido"
    rows = "".join(
        '<div class="seg"><div class="meta">'
        + (f'<span class="spk">{_escape(s.speaker)}</span>' if s.speaker else "")
        + f'<span class="ts">{format_duration(s.start_seconds)}</span>'
        f"</div><p>{_escape(s.text)}</p></div>"
        for s in job.segments
    )
    html = f"""<!doctype html><html><head><meta charset="utf-8">
    <style>{_STYLE}</style></head><body>
    <h1>{_escape(job.original_filename)}</h1>
    <div class="sub">{format_duration(job.duration_seconds)} &middot; {language} &middot; {job.model}</div>
    {rows}
    </body></html>"""
    return HTML(string=html).write_pdf()
