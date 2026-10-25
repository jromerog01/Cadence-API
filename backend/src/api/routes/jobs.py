import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator, Literal
from urllib.parse import quote
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import Response, StreamingResponse
from rq import Queue
from rq.job import Job as RQJob

from adapters.db import new_session
from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.pdf_exporter import to_pdf
from adapters.postgres_repo import PostgresJobRepository
from api.deps import get_audio_probe, get_current_user, get_queue, get_repo
from api.job_creation import (
    ALLOWED_EXTENSIONS,
    MAX_UPLOAD_BYTES,
    check_concurrency_limit,
    finalize_job,
    storage_dir,
)
from api.schemas import JobOut
from domain.exporters import TEXT_EXPORTERS
from domain.models import User

ExportFormat = Literal["txt", "md", "json", "srt", "vtt", "pdf"]

EXPORT_MIME_TYPES: dict[str, str] = {
    "txt": "text/plain; charset=utf-8",
    "md": "text/markdown; charset=utf-8",
    "json": "application/json",
    "srt": "application/x-subrip",
    "vtt": "text/vtt",
    "pdf": "application/pdf",
}

router = APIRouter()

SSE_POLL_INTERVAL_SECONDS = 1.0
CHUNK_SIZE = 1024 * 1024


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
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
    probe: FfmpegAudioProbe = Depends(get_audio_probe),
):
    if not file.filename:
        raise HTTPException(400, "Falta el nombre de archivo")

    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Formato no soportado: {ext or 'desconocido'}")

    check_concurrency_limit(repo)

    job_id = uuid4()
    dest = storage_dir() / f"{job_id}{ext}"
    size_bytes = _save_upload(file, dest)

    return finalize_job(
        job_id=job_id,
        owner_id=current_user.id,
        original_filename=file.filename,
        dest=dest,
        mime_type=file.content_type,
        size_bytes=size_bytes,
        model=model,
        language=language,
        repo=repo,
        queue=queue,
        probe=probe,
    )


@router.get("", response_model=list[JobOut])
def list_jobs(
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
):
    jobs = repo.list_jobs(current_user.id, limit=100, offset=0)
    return [JobOut.from_domain(j) for j in jobs]


@router.get("/{job_id}", response_model=JobOut)
def get_job(
    job_id: UUID,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
):
    job = repo.get_job(job_id)
    if job is None or job.owner_id != current_user.id:
        raise HTTPException(404, "Job not found")
    return JobOut.from_domain(job)


@router.delete("/{job_id}", status_code=204)
def delete_job(
    job_id: UUID,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
):
    job = repo.get_job(job_id, include_segments=False)
    if job is None or job.owner_id != current_user.id:
        raise HTTPException(404, "Job not found")

    try:
        RQJob.fetch(str(job_id), connection=queue.connection).cancel()
    except Exception:
        pass  # already started, already finished, or never queued — fine either way

    Path(job.stored_path).unlink(missing_ok=True)
    repo.delete_job(job_id)


@router.get("/{job_id}/export")
def export_job(
    job_id: UUID,
    format: ExportFormat,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
):
    job = repo.get_job(job_id)
    if job is None or job.owner_id != current_user.id:
        raise HTTPException(404, "Job not found")
    if job.status != "done":
        raise HTTPException(409, "El trabajo todavía no tiene una transcripción lista")

    content: bytes
    if format == "pdf":
        content = to_pdf(job)
    else:
        content = TEXT_EXPORTERS[format](job).encode("utf-8")

    base_name = Path(job.original_filename).stem
    filename = f"{base_name}.{format}"
    # Content-Disposition headers are latin-1 only; a tilde or ñ in the
    # original filename raises UnicodeEncodeError unless it's RFC 5987
    # percent-encoded in a filename* fallback.
    ascii_filename = filename.encode("ascii", "replace").decode("ascii").replace("?", "_")
    return Response(
        content=content,
        media_type=EXPORT_MIME_TYPES[format],
        headers={
            "Content-Disposition": (
                f'attachment; filename="{ascii_filename}"; '
                f"filename*=UTF-8''{quote(filename)}"
            )
        },
    )


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
def job_events(
    job_id: UUID,
    current_user: User = Depends(get_current_user),
    repo: PostgresJobRepository = Depends(get_repo),
):
    job = repo.get_job(job_id, include_segments=False)
    if job is None or job.owner_id != current_user.id:
        raise HTTPException(404, "Job not found")
    return StreamingResponse(
        _stream_job_events(job_id),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
