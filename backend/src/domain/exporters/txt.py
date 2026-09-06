from domain.exporters._util import format_duration
from domain.models import Job


def to_txt(job: Job) -> str:
    language = job.detected_language or job.language or "desconocido"
    header = (
        f"{job.original_filename}\n"
        f"Duración: {format_duration(job.duration_seconds)} · Idioma: {language} · Modelo: {job.model}\n\n"
    )
    body = "\n\n".join(
        f"[{format_duration(s.start_seconds)}] {s.text}" for s in job.segments
    )
    return header + body
