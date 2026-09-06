import os
import shutil
from pathlib import Path
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from rq import Queue

from adapters.postgres_repo import PostgresJobRepository
from api.deps import get_queue, get_repo
from api.schemas import JobOut
from domain.models import DEFAULT_USER_ID
from worker.tasks import transcribe_job

router = APIRouter()


def _storage_dir() -> Path:
    path = Path(os.environ.get("AUDIO_STORAGE_DIR", "/data/audio"))
    path.mkdir(parents=True, exist_ok=True)
    return path


@router.post("", status_code=201, response_model=JobOut)
def create_job(
    file: UploadFile = File(...),
    repo: PostgresJobRepository = Depends(get_repo),
    queue: Queue = Depends(get_queue),
):
    if not file.filename or not file.filename.lower().endswith(".wav"):
        raise HTTPException(400, "Fase 1 solo acepta .wav")

    job_id = uuid4()
    dest = _storage_dir() / f"{job_id}.wav"
    with dest.open("wb") as out:
        shutil.copyfileobj(file.file, out)

    job = repo.create_job(
        id=job_id,
        owner_id=DEFAULT_USER_ID,
        original_filename=file.filename,
        stored_path=str(dest),
        mime_type=file.content_type,
        size_bytes=dest.stat().st_size,
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
