from domain.exporters._util import format_duration
from domain.models import Job


def to_markdown(job: Job) -> str:
    language = job.detected_language or job.language or "desconocido"
    header = (
        f"# {job.original_filename}\n\n"
        f"> Duración: {format_duration(job.duration_seconds)}"
        f" · Idioma: `{language}` · Modelo: `{job.model}`\n\n---\n\n"
    )
    blocks = []
    for s in job.segments:
        speaker = f"**{s.speaker}** " if s.speaker else ""
        blocks.append(f"{speaker}`{format_duration(s.start_seconds)}`\n\n{s.text}")
    return header + "\n\n".join(blocks)
