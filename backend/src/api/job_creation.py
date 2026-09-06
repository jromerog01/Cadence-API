import os
from pathlib import Path
from uuid import UUID

from fastapi import HTTPException
from rq import Queue

from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.model_catalog import get_enabled_models
from adapters.postgres_repo import PostgresJobRepository
from api.schemas import JobOut
from domain.models import DEFAULT_USER_ID
from worker.tasks import transcribe_job

ALLOWED_EXTENSIONS = {".mp3", ".m4a", ".ogg", ".opus", ".flac", ".wav", ".webm", ".mp4"}
MAX_UPLOAD_BYTES = int(os.environ.get("AUDIO_MAX_SIZE_BYTES", str(500 * 1024 * 1024)))
MAX_CONCURRENT_JOBS = int(os.environ.get("MAX_CONCURRENT_JOBS", "5"))


def storage_dir() -> Path:
    path = Path(os.environ.get("AUDIO_STORAGE_DIR", "/data/audio"))
    path.mkdir(parents=True, exist_ok=True)
    return path


def check_concurrency_limit(repo: PostgresJobRepository) -> None:
    if repo.count_active_jobs() >= MAX_CONCURRENT_JOBS:
        raise HTTPException(
            429,
            f"Ya hay {MAX_CONCURRENT_JOBS} trabajos en cola o procesando; espera a que terminen",
        )


def finalize_job(
    *,
    job_id: UUID,
    original_filename: str,
    dest: Path,
    mime_type: str | None,
    size_bytes: int,
    model: str | None,
    language: str | None,
    repo: PostgresJobRepository,
    queue: Queue,
    probe: FfmpegAudioProbe,
) -> JobOut:
    enabled_models = {m.name for m in get_enabled_models()}
    chosen_model = model or os.environ.get("WHISPER_MODEL", "tiny")
    if chosen_model not in enabled_models:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, f"Modelo no disponible: {chosen_model}")

    try:
        audio_info = probe.probe(dest)
    except ValueError:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, "No se pudo leer el archivo como audio")

    if not audio_info.has_audio_stream:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, "El archivo no contiene una pista de audio")

    job = repo.create_job(
        id=job_id,
        owner_id=DEFAULT_USER_ID,
        original_filename=original_filename,
        stored_path=str(dest),
        mime_type=mime_type,
        size_bytes=size_bytes,
        duration_seconds=audio_info.duration_seconds,
        model=chosen_model,
        language=language or None,
    )
    queue.enqueue(transcribe_job, str(job.id), job_timeout=3600)
    return JobOut.from_domain(job)
