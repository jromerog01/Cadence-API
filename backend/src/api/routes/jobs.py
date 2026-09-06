import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from rq import Queue

from adapters.db import new_session
from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.model_catalog import get_enabled_models
from adapters.postgres_repo import PostgresJobRepository
from api.deps import get_audio_probe, get_queue, get_repo
from api.schemas import JobOut
from domain.models import DEFAULT_USER_ID
from worker.tasks import transcribe_job

router = APIRouter()

SSE_POLL_INTERVAL_SECONDS = 1.0

ALLOWED_EXTENSIONS = {".mp3", ".m4a", ".ogg", ".opus", ".flac", ".wav", ".webm", ".mp4"}
MAX_UPLOAD_BYTES = int(os.environ.get("AUDIO_MAX_SIZE_BYTES", str(500 * 1024 * 1024)))
CHUNK_SIZE = 1024 * 1024


def _storage_dir() -> Path:
    path = Path(os.environ.get("AUDIO_STORAGE_DIR", "/data/audio"))
    path.mkdir(parents=True, exist_ok=True)
    return path


def _save_upload(file: UploadFile, dest: Path) -> int:
    size = 0
    with dest.open("wb") as out:
        while chunk := file.file.read(CHUNK_SIZE):
            size += len(chunk)
            if size > MAX_UPLOAD_BYTES:
                out.close()
                dest.unlink(missing_ok=True)
                raise HTTPException(
                    413, f"El archivo supera el límite de {MAX_UPLOAD_BYTES // (1024 * 1024)} MB"
                )
            out.write(chunk)
    return size


@router.post("", status_code=201, response_model=JobOut)
def create_job(
    file: UploadFile = File(...),
    model: str | None = Form(default=None),
    language: str | None = Form(default=None),
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
    probe: FfmpegAudioProbe = Depends(get_audio_probe),
):
    if not file.filename:
        raise HTTPException(400, "Falta el nombre de archivo")

    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Formato no soportado: {ext or 'desconocido'}")

    enabled_models = {m.name for m in get_enabled_models()}
    chosen_model = model or os.environ.get("WHISPER_MODEL", "tiny")
    if chosen_model not in enabled_models:
        raise HTTPException(400, f"Modelo no disponible: {chosen_model}")

    job_id = uuid4()
    dest = _storage_dir() / f"{job_id}{ext}"
    size_bytes = _save_upload(file, dest)

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
        original_filename=file.filename,
        stored_path=str(dest),
        mime_type=file.content_type,
        size_bytes=size_bytes,
        duration_seconds=audio_info.duration_seconds,
        model=chosen_model,
        language=language or None,
    )
    queue.enqueue(transcribe_job, str(job.id), job_timeout=3600)
    return JobOut.from_domain(job)


@router.get("", response_model=list[JobOut])
def list_jobs(repo: PostgresJobRepository = Depends(get_repo)):
    jobs = repo.list_jobs(DEFAULT_USER_ID, limit=100, offset=0)
    return [JobOut.from_domain(j) for j in jobs]


@router.get("/{job_id}", response_model=JobOut)
def get_job(job_id: UUID, repo: PostgresJobRepository = Depends(get_repo)):
    job = repo.get_job(job_id)
    if job is None:
        raise HTTPException(404, "Job not found")
    return JobOut.from_domain(job)


def _sse(event: str, data: dict) -> str:
    return f"event: {event}\ndata: {json.dumps(data)}\n\n"


def _stream_job_events(job_id: UUID) -> Iterator[str]:
    while True:
        session = new_session()
        try:
            repo = PostgresJobRepository(session)
            job = repo.get_job(job_id, include_segments=False)
        finally:
            session.close()

        if job is None:
            yield _sse("error", {"status": "error", "message": "Job not found"})
            return

        if job.status == "error":
            yield _sse("error", {"status": "error", "message": job.error_message or ""})
            return

        if job.status == "done":
            session = new_session()
            try:
                full_job = PostgresJobRepository(session).get_job(job_id, include_segments=True)
            finally:
                session.close()
            segment_count = len(full_job.segments) if full_job else 0
            yield _sse(
                "done",
                {
                    "status": "done",
                    "segment_count": segment_count,
                    "detected_language": job.detected_language,
                },
            )
            return

        elapsed_seconds = 0.0
        if job.started_at is not None:
            elapsed_seconds = (datetime.now(timezone.utc) - job.started_at).total_seconds()

        yield _sse(
            "progress",
            {
                "progress": job.progress,
                "status": job.status,
                "stage": job.stage,
                "elapsed_seconds": elapsed_seconds,
            },
        )
        time.sleep(SSE_POLL_INTERVAL_SECONDS)


@router.get("/{job_id}/events")
def job_events(job_id: UUID, repo: PostgresJobRepository = Depends(get_repo)):
    if repo.get_job(job_id, include_segments=False) is None:
        raise HTTPException(404, "Job not found")
    return StreamingResponse(
        _stream_job_events(job_id),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
