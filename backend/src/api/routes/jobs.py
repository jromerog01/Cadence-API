import os
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from rq import Queue

from adapters.ffmpeg_probe import FfmpegAudioProbe
from adapters.postgres_repo import PostgresJobRepository
from api.deps import get_audio_probe, get_queue, get_repo
from api.schemas import JobOut
from domain.models import DEFAULT_USER_ID
from worker.tasks import transcribe_job

router = APIRouter()

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
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
    probe: FfmpegAudioProbe = Depends(get_audio_probe),
):
    if not file.filename:
        raise HTTPException(400, "Falta el nombre de archivo")

    ext = Path(file.filename).suffix.lower()
    if ext not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Formato no soportado: {ext or 'desconocido'}")

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
        model=os.environ.get("WHISPER_MODEL", "tiny"),
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
